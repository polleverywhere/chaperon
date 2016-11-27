defmodule Chaperon.Action.HTTP do
  defstruct [
    method: :get,
    path: nil,
    params: %{},
    body: nil
  ]

  @type method :: :get | :post | :put | :patch | :delete

  @type t :: %Chaperon.Action.HTTP{
    method: method,
    path: String.t,
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
      path: path,
      body: data
    }
  end

  def put(path, data) do
    %Chaperon.Action.HTTP{
      method: :put,
      path: path,
      body: data
    }
  end

  def patch(path, data) do
    %Chaperon.Action.HTTP{
      method: :patch,
      path: path,
      body: data
    }
  end

  def delete(path) do
    %Chaperon.Action.HTTP{
      method: :delete,
      path: path
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
