defmodule Chaperon.API.OptionParser do
  @callback parse_options(Map.t()) :: {:ok, Map.t()} | {:error, String.t()}
end

defmodule Chaperon.API.OptionParser.Default do
  alias Chaperon.API.OptionParser
  @behaviour OptionParser

  @impl OptionParser
  def parse_options(options) do
    {:ok, options}
  end
end
