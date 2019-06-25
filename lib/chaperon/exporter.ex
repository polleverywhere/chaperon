defmodule Chaperon.Exporter do
  @moduledoc """
  Metrics exporter behaviour.
  Implemented by all built-in exporter modules (see `Chaperon.Export.*`)
  """

  @type options :: Keyword.t()
  @type metrics_data :: any
  @type output_path :: String.t()
  @type file_paths :: [Strint.t()]

  @callback encode(Chaperon.Session.t(), Keyword.t()) ::
              {:ok, metrics_data} | {:error, String.t()}

  @callback write_output(module, options, metrics_data, output_path) ::
              {:ok, file_paths()} | {:error, String.t()}
end
