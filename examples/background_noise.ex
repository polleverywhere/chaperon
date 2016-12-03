defmodule Example.Scenario.BackgroundNoise do
  use Chaperon.Scenario

  def init(session) do
    session
    # rate: incoming requests per interval
    # interval: spread request rate over this amount of time (in ms)
    |> assign(rate: 25, interval: seconds(1))
    |> ok
  end

  def run(session) do
    session
    |> async(:search, ["foo"])
    ~> search("foo") # same as above
    |> post_data
    |> await_all(:search)
    <~ search # same as above but has no effect since tasks already awaited
    # ~>> search(session, resp) do
    #   # do something with logout response
    #   IO.puts "Got search response: #{inspect resp}"
    # end
    |> loop(:spread_post_data, 10 |> minutes)
  end

  def spread_post_data(session) do
    session
    |> cc_spread(:post_data,
                 round(session.assigns.rate),
                 session.assigns.interval)
    |> await_all(:post_data)
    |> increase_noise
  end

  def search(session, query \\ "WHO AM I?") do
    session
    |> get("/", q: query)
  end

  def post_data(session) do
    if session.config.post_data do
      session
      |> post("/data", json: "hello, world!")
    else
      session
    end
  end

  def increase_noise(session) do
    session
    |> update_assign(rate: &(&1 * 1.025)) # increase by 2.5%
  end
end

defmodule Environment.Production do
  alias Example.Scenario.BackgroundNoise
  use Chaperon.Environment

  scenarios do
    default_config %{
      base_url: "https://www.google.de/search",
      http: %{
        # http (hackney request) parameters
      }
    }
    run BackgroundNoise, %{
      post_data: true,
    }
    run BackgroundNoise, %{
      post_data: true,
    }
  end
end

require Logger

for session <- Environment.Production.run do
  for {action, {:async, name, res}} <- session.results do
    Logger.info "async #{name} -> #{inspect res.status_code}"
  end
end
