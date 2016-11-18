defmodule Example.Scenario.BackgroundNoise do
  alias Canary.Session.Error
  alias __MODULE__

  use Canary.Scenario

  defmodule Session do
    defstruct [
      rate: 25,             # incoming requests per interval
      interval: seconds(1), # spread request rate over this amount of time
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

  def spread_post_data(session = %{rate: r, interval: i}) do
    session
    |> cc_spread(:post_data, r, i)
    |> await_all(:post_data)
  end

  def post_data(session) do
    session
    |> post("/data", %{data: "hello, world!"})
  end
end
