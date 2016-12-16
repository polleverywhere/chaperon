defmodule Chaperon.Export.CSV do
  alias Chaperon.Session
  @separator ","
  @delimiter "\n"

  def encode(%Session{metrics: metrics, results: results}, env \\ []) do
    separator = env |> Keyword.get(:separator, @separator)
    delimiter = env |> Keyword.get(:delimiter, @delimiter)

    encode_header(separator)
    <> delimiter
    <> (metrics |> encode_rows(separator, delimiter))
  end

  @header_fields [
    "action", "total_count", "max", "mean", "median", "min", "stddev",
    "percentile_75", "percentile_90", "percentile_95", "percentile_99",
    "percentile_999", "percentile_9999", "percentile_99999"
  ]

  defp encode_header(separator) do
    @header_fields |> Enum.join(separator)
  end

  defp encode_rows(metrics, separator, delimiter) do
    metrics
    |> Enum.flat_map(fn
      {[:duration, action, url], vals} ->
        encode_runs(vals, "#{action}(#{url})", separator)
      {[:duration, action], vals} ->
        encode_runs(vals, "#{action}", separator)
    end)
    |> Enum.join(delimiter)
  end

  defp encode_runs(runs, prefix, separator) when is_list(runs) do
    runs
    |> Enum.map(&(prefix <> separator <> encode_row(&1, separator)))
  end

  defp encode_runs(run, prefix, seperator) do
    [prefix <> seperator <> encode_row(run, seperator)]
  end

  defp encode_row(vals, separator) when is_map(vals) do
    [
      :total_count, :max, :mean, :median, :min, :stddev,
      {:percentile, 75}, {:percentile, 90}, {:percentile, 95}, {:percentile, 99},
      {:percentile, 999}, {:percentile, 9999}, {:percentile, 99999}
    ]
    |> Enum.map(&(vals[&1]))
    |> Enum.join(separator)
  end
end
