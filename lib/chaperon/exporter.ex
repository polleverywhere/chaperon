defmodule Chaperon.Exporter do
  @moduledoc """
  Metrics exporter behaviour.
  Implemented by all built-in exporter modules (see `Chaperon.Export.*`)
  """

  @type runtime_config :: map
  @type metrics_data :: any
  @type output_path :: String.t()

  @callback encode(Chaperon.Session.t(), Keyword.t()) ::
              {:ok, metrics_data} | {:error, String.t()}

  @callback write_output(module, runtime_config, metrics_data, output_path) ::
              :ok | {:error, String.t()}
end
