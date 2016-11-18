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

    @type t :: %__MODULE__{
      rate: non_neg_integer,
      spread: non_neg_integer,
      session: Canary.Session.t
    }
  end

  @type result :: {:ok, BackgroundNoise.Session.t} | {:error, Error.t}

  @spec init(Canary.Session.t) :: result
  def init(session) do
    {:ok, %BackgroundNoise.Session{session: session}}
  end

  @spec run(BackgroundNoise.Session.t) :: result
  def run(bg_session = %{rate: r, spread: s}) do
    bg_session
    |> async_spread(:post_data, r, s)
    |> await(all: :post_data)
  end
end
