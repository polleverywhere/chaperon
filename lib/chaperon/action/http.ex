defmodule Chaperon.Action.HTTP do
  @moduledoc """
  HTTP based actions to be run in a `Chaperon.Scenario` module for a given
  `Chaperon.Session`.

  This supports `GET`, `POST`, `PUT`, `PATCH`, `DELETE` & `HEAD` requests with
  support for optional headers & query params.
  """

  defmodule Response do
    @type t :: %__MODULE__{
            headers: [{String.t(), String.t()}],
            body: String.t() | binary() | iolist(),
            status: non_neg_integer()
          }

    defstruct headers: [],
              body: <<>>,
              status: nil

    def recv(session, conn, request_ref, url, response \\ %{}) do
      use Chaperon.Session
      use Chaperon.Session.Logging

      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            :unknown ->
              session
              |> log_error("HTTP.recv_response: Unknown message: #{inspect(message)}")
              |> recv(conn, request_ref, url, response)

            {:error, reason = %Mint.HTTP1{}, :closed, _} ->
              session =
                session
                |> log_error("HTTP1 connection closed for #{url}")
                |> add_metric({:http1_disconnect, url}, 1)

              {:error, session, reason}

            {:error, reason = %Mint.HTTP2{}, :closed, _} ->
              session =
                session
                |> log_error("HTTP2 connection closed for #{url}")
                |> add_metric({:http2_disconnect, url}, 1)

              {:error, session, reason}

            {:ok, conn, responses} ->
              response =
                responses
                |> Enum.reduce(response, fn
                  {:done, ^request_ref}, response ->
                    Map.put(response, :done, true)

                  {type, ^request_ref, val}, response ->
                    Map.update(response, type, [val], &[val, &1])

                  msg, response ->
                    session
                    |> log_warn(
                      "HTTP.perform_request: Incoming unexpected message: #{inspect(msg)}"
                    )

                    response
                end)

              if response[:done] do
                %{headers: headers, status: [status]} = response

                headers = List.flatten(headers)

                # TODO: use IOList instead of concatenating binaries?
                body =
                  response
                  |> Map.get(:data, [])
                  |> Enum.reverse()
                  |> Enum.reduce("", fn d, acc -> d <> acc end)

                {:ok, session, conn, %Response{headers: headers, status: status, body: body}}
              else
                session
                |> recv(conn, request_ref, url, response)
              end
          end
      end
    end

    @spec cookies(t()) :: [{String.t(), String.t()}]
    def cookies(%__MODULE__{headers: headers}) do
      headers
      |> Enum.filter(fn {key, _} -> String.match?(key, ~r/\Aset-cookie\z/i) end)
      |> Enum.map(fn {_, value} -> value end)
      |> strip_cookie_attributes
    end

    # Strips attributes like Expires and HttpOnly from cookies. Only the name and
    # value are allowed when sending cookies in requests.
    defp strip_cookie_attributes(cookies) do
      cookies
      |> Enum.map(fn value ->
        String.replace(value, ~r/;.*$/, "", global: false)
      end)
    end
  end

  alias __MODULE__.Response

  defstruct method: :get,
            path: nil,
            headers: %{},
            params: %{},
            body: nil,
            decode: nil,
            callback: nil,
            metrics_url: nil

  @type method :: :get | :post | :put | :patch | :delete | :head

  @type options :: [
          form: map | Keyword.t(),
          json: map | Keyword.t(),
          headers: map | Keyword.t(),
          params: map | Keyword.t(),
          decode: :json | (Response.t() -> any),
          with_result: Chaperon.Session.result_callback(),
          metrics_url: String.t()
        ]

  @type t :: %Chaperon.Action.HTTP{
          method: method,
          path: String.t(),
          headers: map,
          params: map,
          body: binary,
          decode: :json | (Response.t() -> any),
          callback: Chaperon.Session.result_callback(),
          metrics_url: String.t()
        }

  @spec get(String.t(), options) :: t
  def get(path, opts) do
    %Chaperon.Action.HTTP{
      method: :get,
      path: path
    }
    |> add_options(opts)
  end

  @spec post(String.t(), options) :: t
  def post(path, opts) do
    %Chaperon.Action.HTTP{
      method: :post,
      path: path
    }
    |> add_options(opts)
  end

  @spec put(String.t(), options) :: t
  def put(path, opts) do
    %Chaperon.Action.HTTP{
      method: :put,
      path: path
    }
    |> add_options(opts)
  end

  @spec patch(String.t(), options) :: t
  def patch(path, opts) do
    %Chaperon.Action.HTTP{
      method: :patch,
      path: path
    }
    |> add_options(opts)
  end

  @spec delete(String.t(), options) :: t
  def delete(path, opts \\ []) do
    %Chaperon.Action.HTTP{
      method: :delete,
      path: path
    }
    |> add_options(opts)
  end

  alias __MODULE__
  alias Chaperon.Session

  def url(%{path: ""}, %Session{config: %{base_url: base_url}}) do
    base_url <> "/"
  end

  def url(%{path: path}, %Session{config: %{base_url: base_url}}) do
    if is_full_url?(path) do
      path
    else
      base_url <> path
    end
  end

  def url(%{path: path}, _) do
    path
  end

  def is_full_url?("http://" <> _), do: true
  def is_full_url?("https://" <> _), do: true
  def is_full_url?("ws://" <> _), do: true
  def is_full_url?("wss://" <> _), do: true
  def is_full_url?(_), do: false

  def full_url(action = %HTTP{method: method, params: params}, session) do
    url = url(action, session)

    case method do
      :get -> url <> query_params_string(params)
      _ -> url
    end
  end

  def scheme("https"), do: :https
  def scheme("http"), do: :http

  def method(%__MODULE__{method: :get}), do: "GET"
  def method(%__MODULE__{method: :post}), do: "POST"
  def method(%__MODULE__{method: :put}), do: "PUT"
  def method(%__MODULE__{method: :patch}), do: "PATCH"
  def method(%__MODULE__{method: :delete}), do: "DELETE"

  @spec metrics_url(map(), atom() | %{config: nil | keyword() | map()}) :: any()
  def metrics_url(%{metrics_url: metrics_url}, %Session{config: %{base_url: base_url}})
      when not is_nil(metrics_url) do
    base_url <> metrics_url
  end

  def metrics_url(action, session) do
    if session.config[:skip_query_params_in_metrics] do
      action
      |> url(session)
    else
      action
      |> full_url(session)
    end
  end

  def full_path(%{path: path, params: params}), do: path <> query_params_string(params)

  def query_params_string([]), do: ""

  def query_params_string(params) do
    case URI.encode_query(params) do
      "" -> ""
      q -> "?" <> q
    end
  end

  def options(action, session) do
    opts =
      session.config
      |> Map.get(:http, %{})
      |> Enum.into([])
      |> Keyword.merge(params: action.params)

    case hackney_opts(action, session) do
      [] ->
        opts

      hackney_opts ->
        opts
        |> Keyword.merge(hackney: hackney_opts)
    end
  end

  @default_headers %{
    "User-Agent" => "chaperon",
    "Accept" => "*/*"
  }

  @spec add_options(any, Chaperon.Action.HTTP.options()) :: t
  def add_options(action, opts) do
    alias Keyword, as: KW
    import Map, only: [merge: 2]

    headers = opts[:headers] || %{}
    params = opts[:params] || %{}
    decode = opts[:decode]
    callback = opts[:with_result]
    metrics_url = opts[:metrics_url]

    {new_headers, body} =
      opts
      |> KW.delete(:headers)
      |> KW.delete(:params)
      |> KW.delete(:decode)
      |> KW.delete(:with_result)
      |> KW.delete(:metrics_url)
      |> parse_body

    headers =
      action.headers
      |> merge(@default_headers)
      |> merge(headers)
      |> merge(new_headers)

    %{
      action
      | headers: headers,
        params: params,
        body: body,
        decode: decode,
        callback: callback,
        metrics_url: metrics_url
    }
  end

  def perform_request(session, action) do
    use Chaperon.Session.Logging

    method = HTTP.method(action)
    url = HTTP.url(action, session)
    uri = %URI{host: host, path: path, port: port, scheme: scheme} = URI.parse(url)
    body = action.body || ""
    options = HTTP.options(action, session)

    # Mint.HTTP1.Request.encode_headers

    headers =
      action.headers
      |> Enum.map(fn {key, val} -> {key |> to_string(), val |> to_string} end)

    with {:ok, session, conn} <- open_connection(session, uri),
         {:ok, session, conn, request_ref} <-
           send_request(session, conn, method, path, headers, body),
         {:ok, session, conn, response} <- Response.recv(session, conn, request_ref, url) do
      with {:ok, _conn} <- Mint.HTTP.close(conn) do
        session
        |> log_debug("HTTP.perform_request: Closed connection for #{url}")
      else
        err ->
          session
          |> log_error("Failed to close HTTP connection to #{url} : #{inspect(err)}")
      end

      {:ok, session, response}
    else
      {:error, %Chaperon.Session{} = session, reason} ->
        session
        |> log_error("HTTP.perform_request failed: #{inspect(reason)}")
        |> Chaperon.Session.add_metric({:http_req_failed, {url, reason}}, 1)

        {:error, session, reason}

      error ->
        session
        |> log_error("HTTP.perform_request unknown failure: #{inspect(error)}")

        {:error, session, error}
    end
  end

  defp open_connection(session, %URI{host: host, port: port, scheme: scheme}) do
    use Chaperon.Session.Logging
    use Chaperon.Session

    session =
      session
      |> time({:http_open, host}, fn session ->
        with {:ok, conn} <- Mint.HTTP.connect(HTTP.scheme(scheme), host, port) do
          session
          |> assign(http_conn: conn)
        else
          {:error, reason} ->
            session
            |> log_error("HTTP.open_connection: Error: #{inspect(reason)}")
            |> assign(http_conn_error: reason)
        end
      end)

    case session.assigned[:http_conn_error] do
      nil -> {:ok, session, session.assigned[:http_conn]}
      error -> {:error, session, error}
    end
  end

  defp send_request(session, conn, method, path, headers, body) do
    # TODO: time this as well
    with {:ok, conn, request_ref} <- Mint.HTTP.request(conn, method, path, headers, body) do
      {:ok, session, conn, request_ref}
    end
  end

  defp hackney_opts(_action, session) do
    opts = [
      cookie: session.cookies,
      basic_auth: session.config[:basic_auth],
      pool: :chaperon
    ]

    opts
    |> Enum.map(&hackney_opt/1)
    |> Enum.reject(&is_nil/1)
  end

  # don't pass if no value set
  defp hackney_opt({_key, nil}), do: nil
  # don't pass empty list of cookies
  defp hackney_opt({:cookie, []}), do: nil
  # pass everything else as hackney option
  defp hackney_opt(opt), do: opt

  defp parse_body([]), do: {%{}, ""}

  defp parse_body(json: data) when is_list(data) do
    data =
      if Keyword.keyword?(data) do
        data |> Enum.into(%{})
      else
        data
      end

    data
    |> json_body
  end

  defp parse_body(json: data), do: data |> json_body
  defp parse_body(form: data), do: data |> form_body

  defp json_body(data) do
    {
      %{"Content-Type" => "application/json", "Accept" => "application/json"},
      data |> Poison.encode!()
    }
  end

  defp form_body(data) do
    {
      %{"Content-Type" => "application/x-www-form-urlencoded"},
      data |> URI.encode_query()
    }
  end
end

defimpl Chaperon.Actionable, for: Chaperon.Action.HTTP do
  alias Chaperon.Action.Error
  alias Chaperon.Action.HTTP
  import Chaperon.Timing
  import Chaperon.Session
  use Chaperon.Session.Logging

  def run(action, session) do
    full_url = HTTP.full_url(action, session)

    session
    |> log_info("#{action.method |> to_string |> String.upcase()} #{full_url}")

    start = timestamp()

    case session
         |> HTTP.perform_request(action) do
      {:ok, session, response} ->
        session
        |> add_result(action, response)
        |> add_metric(
          {action.method, HTTP.metrics_url(action, session)},
          timestamp() - start
        )
        |> store_response_cookies(response)
        |> run_callback_if_defined(action, response)
        |> ok

      {:error, session, reason} ->
        session
        |> log_error("HTTP action #{action} failed")

        session =
          session
          |> run_error_callback(action, reason)

        {:error, %Error{reason: reason, action: action, session: session}}
    end
  end

  def run_callback_if_defined(session, action, response) do
    case response.status do
      code when code in 200..399 ->
        session
        |> log_debug("HTTP Response #{action} : #{code}")
        |> run_callback(action, response)

      code ->
        session
        |> log_warn("HTTP Response #{action} failed with status code: #{code}")
        |> log_warn(response.body)
        |> run_error_callback(action, response)
    end
  end

  def abort(action, session) do
    # TODO
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.HTTP do
  alias Chaperon.Action.HTTP

  @methods [:get, :post, :put, :patch, :delete, :head]
  @method_strings @methods
                  |> Enum.map(&{&1, &1 |> Kernel.to_string() |> String.upcase()})
                  |> Enum.into(%{})

  def to_string(http) do
    "#{@method_strings[http.method]} #{HTTP.full_url(http, %{})}"
  end
end
