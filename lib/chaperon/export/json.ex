defmodule Chaperon.Export.JSON do
  @moduledoc """
  JSON metrics export module.
  """

  alias Chaperon.Scenario.Metrics

  @columns [
    :total_count, :max, :mean, :min
  ] ++ (for p <- Metrics.percentiles, do: {:percentile, p})

  @doc """
  Encodes metrics of given `session` into JSON format.
  """
  def encode(session, _opts \\ []) do
    session.metrics
    |> Enum.map(fn
      {[:duration, :call, {mod, func}], vals} ->
        %{action: :call, module: (inspect mod), function: func, metrics: metrics(vals)}
      {[:duration, :call, func], vals} ->
        %{action: :call, function: func, metrics: metrics(vals)}
      {[:duration, action, url], vals} ->
        %{action: action, url: url, metrics: metrics(vals)}
      {[:duration, action], vals} ->
        %{action: action, metrics: metrics(vals)}
    end)
    |> Poison.encode!
  end

  def metrics([]), do: %{}

  def metrics([v | vals]) do
    Map.merge(metrics(v), metrics(vals))
  end

  def metrics(vals) when is_map(vals) do
    metrics =
      vals
      |> Map.take(@columns)
      |> Enum.map(fn
        {{:percentile, p}, val} ->
          {"percentile_#{p}", round(val)}
        {k, v} ->
          {k, round(v)}
      end)
      |> Enum.into(%{})

    session_name = vals[:session_name]

    if session_name && String.trim(session_name) != "" do
      %{vals[:session_name] => metrics}
    else
      metrics
    end
  end
end
