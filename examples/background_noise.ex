defmodule BackgroundNoise.Scenario do
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
    # same as above
    ~> search("foo")
    # await async search results
    |> await(:search)
    # same as above
    <~ search
    |> spread_post_data
  end

  def spread_post_data(session) do
    session
    |> cc_spread(
      :post_data,
      round(session.assigned.rate),
      session.assigned.interval
    )
    |> await_all(:post_data)
    |> increase_noise
  end

  def search(session, query \\ "WHO AM I?") do
    session
    |> get("/", params: [q: query])

    # # we could store a potential JSON response inside the session for further use:
    # |> get("/", params: [q: query], decode: :json, with_result: &add_search_result(&1, query, &2))
  end

  def post_data(session) do
    if session.config.post_data do
      session
      |> post("/", json: %{message: "hello, world!"})
    else
      session
    end
  end

  def increase_noise(session) do
    session
    # increase by 2.5%
    |> update_assign(rate: &(&1 * 1.025))
  end

  def add_search_result(session, query, result) do
    session
    |> update_assign(search_results: &Map.put(&1 || %{}, query, result))
  end
end

defmodule BackgroundNoise.LoadTest.Production do
  use Chaperon.LoadTest

  def default_config,
    do: %{
      # scenario_timeout: 12_000,
      base_url: "http://google.com/",
      http:
        %{
          # additional http (hackney request) parameters, if needed
        }
    }

  def scenarios,
    do: [
      {BackgroundNoise.Scenario,
       %{
         post_data: true
       }},
      {BackgroundNoise.Scenario,
       %{
         post_data: true
       }}
    ]
end

Chaperon.run_load_test(BackgroundNoise.LoadTest.Production, print_results: true)
