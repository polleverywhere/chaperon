defmodule Chaperon.Scenario.Metrics do
  @moduledoc """
  This module calculates histogram data for a session's metrics.
  It uses the `Histogrex` library to calculate the histograms.
  """

  use Histogrex
  alias __MODULE__
  alias Chaperon.Session

  template :durations, min: 1, max: 10_000_000, precision: 3

  @type metric :: atom | {atom, any}
  @type metric_type :: atom
  @type metric_options :: [
    filter: (metric -> boolean) | [metric_type]
  ]

  @doc """
  Replaces base metrics for a given `session` with the histogram values for them.

  Valid options:

      filter: fn(metric) -> true | false end
      filter: [metric_type]

  Example:

      # only track custom scenarios, function calls & http POST requests
      Chaperon.Scenario.Metrics.add_histogram_metrics(session, metrics: [
        filter: fn
          {type, _} when type in [:run_scenario, :call, :post] -> true
          _ -> false
        end
      ])

      # or just pass a list of types:
      Chaperon.Scenario.Metrics.add_histogram_metrics(session, metrics: [
        filter: [:run_scenario, :call, :post]
      ]
  """
  @spec add_histogram_metrics(Session.t, metric_options) :: Session.t
  def add_histogram_metrics(session, options \\ []) do
    metrics = histogram_metrics(session, options)
    reset()
    %{session | metrics: metrics}
  end

  def reset do
    Metrics.delete(:durations)
    Metrics.reduce(:ok, fn {name, _}, _ ->
      Metrics.delete(:durations, name)
    end)
  end

  @doc false
  def histogram_metrics(session = %Session{}, options) do
    session
    |> record_histograms(options)

    Metrics.reduce(%{}, fn {name, hist}, metrics ->
      Map.put(metrics, name, histogram_vals(hist))
    end)
  end

  @percentiles [
    10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 75.0,
    80.0, 85.0, 90.0, 95.0, 99.0, 99.9, 99.99, 99.999
  ]

  def percentiles, do: @percentiles

  @doc false
  def histogram_vals({k, hist}) do
    {k, histogram_vals(hist)}
  end

  def histogram_vals(hist) do
    hist
    |> percentiles
    |> Map.merge(%{
      :total_count => Metrics.total_count(hist),
      :min => Metrics.min(hist),
      :mean => Metrics.mean(hist),
      :max => Metrics.max(hist)
    })
  end

  def percentiles(hist) do
    @percentiles
    |> Enum.map(&{{:percentile, &1}, Metrics.value_at_quantile(hist, &1)})
    |> Enum.into(%{})
  end

  @doc false
  def record_histograms(session, options) do
    filter = case Keyword.get(options, :filter) do
      nil ->
        nil

      f when is_function(f) ->
        f

      types when is_list(types) ->
        types = MapSet.new(types)

        fn
          {type, _} ->
            passes_filter?(types, type)

          type ->
            passes_filter?(types, type)
        end
    end

    session.metrics
    |> Enum.each(fn {k, v} ->
      if filter do
        if filter.(k) do
          record_metric(k, v)
        end
      else
        record_metric(k, v)
      end
    end)
  end

  def passes_filter?(types, type) do
    if MapSet.member?(types, type) do
      true
    else
      false
    end
  end

  @doc false
  def record_metric(_, []), do: :ok
  def record_metric(k, [v | vals]) do
    record_metric(k, v)
    record_metric(k, vals)
  end

  @doc false
  def record_metric(k, {:async, _name, val}) when is_number(val) do
    record_metric(k, val)
  end

  @doc false
  def record_metric(k, val) when is_number(val) do
    Metrics.record!(:durations, k, val)
  end
end
