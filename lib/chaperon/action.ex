defmodule Chaperon.Action do
  @moduledoc """
  Helper functions to be used with `Chaperon.Actionable`.
  """

  @doc """
  Retries `action` within `session` by calling `Chaperon.Actionable.abort/2`
  followed by `Chaperon.Actionable.run/2`.
  """
  def retry(action, session) do
    with {:ok, action, session} <- Chaperon.Actionable.abort(action, session) do
      Chaperon.Actionable.run(action, session)
    end
  end

  @doc """
  Returns a `Chaperon.Action.Error` for the given arguments.
  """
  def error(action, session, reason) do
    %Chaperon.Action.Error{
      reason: reason,
      action: action,
      session: session
    }
  end

  @doc """
  Every `Chaperon.Actionable` can now expose a `callback` field.
  `callback` can be either:

  - a callback function:

      (Chaperon.Session.t, any | {:error, any}) -> any

  - a map containing callback and error functions:

      %{
        ok:    (Chaperon.Session.t, any) -> any,
        error: (Chaperon.Session.t, any) -> any
      }

  When defining just a single callback function, it will be called in both
  success and error cases (passed in as `{:error, reason}`).
  To handle each case individually, you can just use pattern matching:

      session
      |> post("/greet", json: [hello: "world!"], with_result: fn
        (session, {:error, reason}) ->
          # handle error case here
          session
          |> log_error("Failed to greet")

        (session, %HTTPoison.Response{body: response}) ->
          # do something with successful response here
          session
          |> log_info("Greeted successfully!")
      end)
  """
  def callback(%{callback: %{ok: cb}}),
    do: cb
  def callback(%{callback: cb}),
    do: cb

  def error_callback(%{callback: %{error: cb}}),
    do: cb
  def error_callback(%{callback: cb}),
    do: fn(session, resp) ->
      cb.(session, {:error, resp})
    end
  def error_callback(_),
    do: nil
end
