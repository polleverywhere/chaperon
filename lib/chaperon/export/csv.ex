defmodule Chaperon.Export.CSV do
  @moduledoc """
  CSV metrics export module.
  """

  @behaviour Chaperon.Exporter

  alias Chaperon.Util
  alias Chaperon.Scenario.Metrics

  @separator ","
  @delimiter "\n"

  @doc """
  Encodes metrics of given `session` into CSV format.
  """
  def encode(session, opts \\ []) do
    separator = opts |> Keyword.get(:separator, @separator)
    delimiter = opts |> Keyword.get(:delimiter, @delimiter)

    data = encode_header(separator) <> delimiter <> (session |> encode_rows(separator, delimiter))

    {:ok, data}
  end

  def write_output(lt_mod, runtime_config, data, filename) do
    Chaperon.write_output_to_file(lt_mod, runtime_config, data, filename <> ".csv")
  end

  @header_fields [
                   "session_action_name",
                   "total_count",
                   "max",
                   "mean",
                   "min"
                 ] ++ for(p <- Metrics.percentiles(), do: "percentile_#{p}")

  @columns [
             :total_count,
             :max,
             :mean,
             :min
           ] ++ for(p <- Metrics.percentiles(), do: {:percentile, p})

  defp encode_header(separator) do
    @header_fields
    |> Enum.join(separator)
  end

  defp encode_rows(session, separator, delimiter) do
    session.metrics
    |> Enum.flat_map(fn
      {{:call, {mod, func}}, vals} ->
        mod_name = Util.shortened_module_name(mod)
        encode_runs(vals, "call(#{mod_name}.#{func})", separator)

      {{action, url}, vals} ->
        encode_runs(vals, "#{action}(#{url})", separator)

      {action, vals} ->
        encode_runs(vals, "#{action}", separator)
    end)
    |> Enum.join(delimiter)
  end

  defp encode_runs(runs, action_name, separator) when is_list(runs) do
    runs
    |> Enum.map(&encode_row(&1, action_name, separator))
  end

  defp encode_runs(run, action_name, separator) do
    [encode_row(run, action_name, separator)]
  end

  defp encode_row(vals, action_name, separator) when is_map(vals) do
    session_name = vals[:session_name]

    "#{session_name} #{action_name}" <> separator <> encode_row_values(vals, separator)
  end

  defp encode_row_values(vals, separator) do
    @columns
    |> Enum.map(&round(vals[&1]))
    |> Enum.join(separator)
  end
end
