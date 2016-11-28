defmodule Chaperon.Action.HTTP do
  defstruct [
    method: :get,
    path: nil,
    headers: %{},
    params: %{},
    response: nil,
    body: nil
  ]

  @type method :: :get | :post | :put | :patch | :delete

  @type t :: %Chaperon.Action.HTTP{
    method: method,
    path: String.t,
    headers: map,
    params: map,
    response: HTTPoison.Response.t | HTTPoison.AsyncResponse.t,
    body: binary
  }

  def get(path, params) do
    %Chaperon.Action.HTTP{
      method: :get,
      path: path,
      params: params
    }
  end

  def post(path, data) do
    %Chaperon.Action.HTTP{
      method: :post,
      path: path
    }
    |> add_body(data)
  end

  def put(path, data) do
    %Chaperon.Action.HTTP{
      method: :put,
      path: path
    }
    |> add_body(data)
  end

  def patch(path, data) do
    %Chaperon.Action.HTTP{
      method: :patch,
      path: path
    }
    |> add_body(data)
  end

  def delete(path) do
    %Chaperon.Action.HTTP{
      method: :delete,
      path: path
    }
  end

  def url(action, session) do
    session.config.base_url <> "/" <> action.path
  end

  def options(action, session) do
    session.config.http
    |> Keyword.merge(params: action.params)
  end

  def add_body(action, body) do
    import Map, only: [merge: 2]

    {new_headers, body} = parse_body(body)
    %{ action |
      headers: action.headers |> merge(new_headers),
      body: body
    }
  end

  defp parse_body(json: data) when is_list(data) do
    data = if Keyword.keyword?(data) do
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
      %{"Content-Type": "application/json"},
      data |> Poison.encode!
    }
  end

  defp form_body(data) do
    {
      %{"Content-Type": "x-www-form-urlencoded"},
      data |> URI.encode_query
    }
  end
end

defimpl Chaperon.Actionable, for: Chaperon.Action.HTTP do
  alias Chaperon.Action.Error
  alias Chaperon.Action.HTTP
  import Chaperon.Session, only: [update_action: 3]
  require Logger

  def run(action, session) do
    case HTTPoison.request(
      action.method,
      HTTP.url(action, session),
      action.body,
      action.headers,
      HTTP.options(action, session)
    ) do
      {:ok, response} ->
        {:ok, session |> update_action(action, %{action | response: response})}

      {:error, reason} ->
        Logger.error "HTTP action [#{action.method} #{action.path}] failed: #{inspect reason}"
        {:error, %Error{reason: reason, action: action, session: session}}
    end
  end

  def abort(action, session) do
    # TODO
    {:ok, session}
  end

  def retry(action, session) do
    Chaperon.Action.retry(action, session)
  end

  def done?(%{response: nil}, _),
    do: false
  def done?(%{response: _}, _),
    do: true
end
