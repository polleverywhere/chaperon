defmodule Example.Scenario.BackgroundNoise do
  alias Canary.Session.Error
  alias __MODULE__

  use Canary.Scenario

  defmodule Session do
    defstruct [
      rate: 25,     # incoming requests per spread milliseconds
      spread: 1000, # spread request rate over this amount of milliseconds
      session: nil
    ]
  end

  def init(session) do
    {:ok, %BackgroundNoise.Session{session: session}}
  end

  def run(session) do
    session
    |> loop(:spread_post_data, 10 |> minutes)
  end

  def spread_post_data(session = %{rate: r, spread: s}) do
    session
    |> async_spread(:post_data, r, s)
    |> await(all: :post_data)
  end
end
