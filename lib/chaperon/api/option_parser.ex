defmodule Chaperon.API.OptionParser do
  @callback parse_options(Map.t()) ::
              {:ok, Chaperon.LoadTest.lt_conf(), Map.t()}
              | {:ok, [{Chaperon.LoadTest.lt_conf(), Map.t()}]}
              | {:error, String.t()}
end

defmodule Chaperon.API.OptionParser.Default do
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
