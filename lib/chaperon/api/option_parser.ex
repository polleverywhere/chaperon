defmodule Chaperon.API.OptionParser do
  @moduledoc """
  HTTP API option parser behaviour that can be implemented to customize, extend
  and modify any incoming web request options to be used when scheduling new
  load tests.
  Is expected to return a load test configuration to be run and used by
  `Chaperon.Master.schedule_load_test/1`.
  """

  @callback parse_options(%{options: Map.t(), test: String.t()}) ::
              {:ok, Chaperon.LoadTest.lt_conf(), Map.t()}
              | {:ok, [{Chaperon.LoadTest.lt_conf(), Map.t()}]}
              | {:error, String.t()}
end

defmodule Chaperon.API.OptionParser.Default do
  @moduledoc """
  Default option parser that uses the given `test` and `options` values to be used
  as the load test module to run with the given runtime options.
  """

  alias Chaperon.API.OptionParser
  @behaviour OptionParser

  @impl OptionParser
  def parse_options(args) do
    lt_mod =
      args[:test]
      |> String.split(".")
      |> Module.concat()

    options = args[:options]

    {:ok, lt_mod, options}
  end
end
