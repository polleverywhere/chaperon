defmodule Chaperon.Action.HTTP do
  defstruct [
    method: :get,
    path: nil,
    headers: %{},
    params: %{},
    body: nil
  ]

  @type method :: :get | :post | :put | :patch | :delete

  @type t :: %Chaperon.Action.HTTP{
    method: method,
    path: String.t,
    headers: map,
    params: map,
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
  def run(action, session) do
    # TODO
    {:ok, session}
  end

  def abort(action, session) do
    # TODO
    {:ok, session}
  end

  def retry(action, session) do
    Chaperon.Action.retry(action, session)
  end
end
