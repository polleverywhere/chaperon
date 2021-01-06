defmodule Chaperon.Action.HTTP do
  @moduledoc """
  HTTP based actions to be run in a `Chaperon.Scenario` module for a given
  `Chaperon.Session`.

  This supports `GET`, `POST`, `PUT`, `PATCH`, `DELETE` & `HEAD` requests with
  support for optional headers & query params.
  """

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
          gzip: iodata,
          headers: map | Keyword.t(),
          params: map | Keyword.t(),
          decode: :json | (HTTPoison.Response.t() -> any),
          with_result: Chaperon.Session.result_callback(),
          metrics_url: String.t()
        ]

  @type t :: %Chaperon.Action.HTTP{
          method: method,
          path: String.t(),
          headers: map,
          params: map,
          body: binary,
          decode: :json | (HTTPoison.Response.t() -> any),
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

  defp hackney_opts(_action, session) do
    opts = [
      cookie: session.cookies,
      basic_auth: session.config[:basic_auth],
      pool: :chaperon,
      insecure: session.config[:insecure]
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

  defp parse_body(gzip: data) do
    {
      %{"Content-Encoding" => "gzip"},
      data |> :zlib.gzip()
    }
  end

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

    case HTTPoison.request(
           action.method,
           HTTP.url(action, session),
           action.body || "",
           action.headers,
           HTTP.options(action, session)
         ) do
      {:ok, response} ->
        session
        |> add_result(action, response)
        |> add_request_metrics(action, response, timestamp() - start)
        |> store_response_cookies(response)
        |> run_callback_if_defined(action, response)
        |> ok

      {:error, reason} ->
        session
        |> log_error("HTTP action #{action} failed")

        session =
          session
          |> run_error_callback(action, reason)

        {:error, %Error{reason: reason, action: action, session: session}}
    end
  end

  defp add_request_metrics(
         session,
         action,
         _response = %HTTPoison.Response{status_code: status_code},
         duration
       ) do
    metrics_url = HTTP.metrics_url(action, session)

    session =
      session
      |> add_metric({action.method, metrics_url}, duration)

    case status_code do
      c when c < 400 ->
        session

      c when c in 400..599 ->
        session
        |> add_metric({{:error, {:http, c}}, {action.method, metrics_url}}, duration)
    end
  end

  def run_callback_if_defined(session, action, response) do
    case response.status_code do
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
