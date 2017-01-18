defmodule Chaperon.Scenario.Metrics do
  @moduledoc """
  This module calculates histogram data for a sessions metrics.
  It uses the `:hdr_histogram` Erlang library to calculate the histograms.
  """

  @doc """
  Replaces base metrics for a given `session` with the histogram values for them.
  """
  def add_histogram_metrics(session) do
    histograms = session |> record_metrics

    hist_vals = for {k, hist} <- histograms do
      {k, %{
        :total_count => :hdr_histogram.get_total_count(hist),
        :min => :hdr_histogram.min(hist),
        :mean => :hdr_histogram.mean(hist),
        :median => :hdr_histogram.median(hist),
        :max => :hdr_histogram.max(hist),
        :stddev => :hdr_histogram.stddev(hist),
        {:percentile, 75} => :hdr_histogram.percentile(hist, 75.0),
        {:percentile, 90} => :hdr_histogram.percentile(hist, 90.0),
        {:percentile, 95} => :hdr_histogram.percentile(hist, 95.0),
        {:percentile, 99} => :hdr_histogram.percentile(hist, 99.0),
        {:percentile, 999} => :hdr_histogram.percentile(hist, 99.9),
        {:percentile, 9999} => :hdr_histogram.percentile(hist, 99.99),
        {:percentile, 99999} => :hdr_histogram.percentile(hist, 99.999)
      }}
    end
    |> Enum.into(%{})

    put_in session.metrics, hist_vals
  end

  @doc false
  def record_metrics(session) do
    session.metrics
    |> Enum.reduce(%{}, fn {k,v}, histograms ->
      case histograms[k] do
        nil ->
          {:ok, hist} = :hdr_histogram.open(1000000, 3)
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
