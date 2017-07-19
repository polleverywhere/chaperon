defmodule Chaperon.Scenario.Metrics do
  @moduledoc """
  This module calculates histogram data for a session's metrics.
  It uses the `:hdr_histogram` Erlang library to calculate the histograms.
  """

  @doc """
  Replaces base metrics for a given `session` with the histogram values for them.
  """
  def add_histogram_metrics(session) do
    %{session | metrics: histogram_metrics(session)}
  end

  @doc false
  def histogram_metrics(session = %Chaperon.Session{}) do
    session
    |> record_histograms
    |> Enum.map(&histogram_vals/1)
    |> Enum.into(%{})
  end

  @percentiles [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 75.0, 80.0, 85.0, 90.0, 95.0, 99.0, 99.9, 99.99, 99.999]

  def percentiles, do: @percentiles

  @doc false
  def histogram_vals({k, hist}) do
    {k, histogram_vals(hist)}
  end

  def histogram_vals(hist) do
    Map.merge(percentiles(hist), %{
      :total_count => :hdr_histogram.get_total_count(hist),
      :min => :hdr_histogram.min(hist),
      :mean => :hdr_histogram.mean(hist),
      :median => :hdr_histogram.median(hist),
      :max => :hdr_histogram.max(hist),
      :stddev => :hdr_histogram.stddev(hist),
    })
  end

  def percentiles(hist) do
    @percentiles
    |> Enum.map(&{{:percentile, &1}, :hdr_histogram.percentile(hist, &1)})
    |> Enum.into(%{})
  end

  @doc false
  def record_histograms(session) do
    session.metrics
    |> Enum.reduce(%{}, fn {k, v}, histograms ->
      case histograms[k] do
        nil ->
          {:ok, hist} = :hdr_histogram.open(1_000_000, 3)
          hist |> record_metric(v)
          put_in histograms[k], hist

        hist ->
          hist |> record_metric(v)
          histograms
      end
    end)
    |> Enum.into(%{})
  end

  @doc false
  def record_metric(_hist, []), do: :ok
  def record_metric(hist, [v | vals]) do
    record_metric(hist, v)
    record_metric(hist, vals)
  end

  @doc false
  def record_metric(hist, {:async, _name, val}) when is_number(val) do
    record_metric(hist, val)
  end

  @doc false
  def record_metric(hist, val) when is_number(val) do
    :hdr_histogram.record(hist, val)
  end
end
