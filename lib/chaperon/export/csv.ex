defmodule Chaperon.Export.CSV do
  @moduledoc """
  CSV metrics export module.
  """

  @separator ";"
  @delimiter "\n"

  @doc """
  Encodes metrics of given `session` into CSV format.
  """
  def encode(session, opts \\ []) do
    separator = opts |> Keyword.get(:separator, @separator)
    delimiter = opts |> Keyword.get(:delimiter, @delimiter)

    encode_header(separator)
    <> delimiter
    <> (session |> encode_rows(separator, delimiter))
  end

  @header_fields [
    "session_action_name", "total_count", "max", "mean", "median", "min", "stddev",
    "percentile_75", "percentile_90", "percentile_95", "percentile_99",
    "percentile_999", "percentile_9999", "percentile_99999"
  ]

  @columns [
    :total_count, :max, :mean, :median, :min, :stddev,
    {:percentile, 75}, {:percentile, 90}, {:percentile, 95}, {:percentile, 99},
    {:percentile, 999}, {:percentile, 9999}, {:percentile, 99999}
  ]

  defp encode_header(separator) do
    @header_fields
    |> Enum.join(separator)
  end

  defp encode_rows(session, separator, delimiter) do
    session.metrics
    |> Enum.flat_map(fn
      {[:duration, action, url], vals} ->
        encode_runs(vals, "#{action}(#{url})", separator)
      {[:duration, action], vals} ->
        encode_runs(vals, "#{action}", separator)
    end)
    |> Enum.join(delimiter)
  end

  defp encode_runs(runs, action_name, separator) when is_list(runs) do
    runs
    |> Enum.map(&(encode_row(&1, action_name, separator)))
  end

  defp encode_runs(run, action_name, seperator) do
    [encode_row(run, action_name, seperator)]
  end

  defp encode_row(vals, action_name, separator) when is_map(vals) do
    session_name = vals[:session_name]

    "#{session_name} #{action_name}"
    <> separator
    <> encode_row_values(vals, separator)
  end

  defp encode_row_values(vals, separator) do
    @columns
    |> Enum.map(&(round(vals[&1])))
    |> Enum.join(separator)
  end
end
