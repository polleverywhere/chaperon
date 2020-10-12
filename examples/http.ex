# mix deps.get && mix run examples/http.ex && cat $(find results -name *csv) | sed 's/,/ ,/g' | column -t -s, | less -S

defmodule Scenario.Http do
  use Chaperon.Scenario

  def run(session) do
    session
    |> get("/news")
  end
end

defmodule LoadTest.Http do
  use Chaperon.LoadTest

  def default_config,
    do: %{
      base_url: "http://bbc.com"
    }

  def scenarios,
    do: [
      {{10, Scenario.Http},
       %{
         run: %{
           iterations: 10
         }
       }}
    ]
end

Chaperon.run_load_test(LoadTest.Http)
