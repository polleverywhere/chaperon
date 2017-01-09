defmodule Chaperon.Scenario do
  defstruct [
    module: nil
  ]

  @type t :: %Chaperon.Scenario{
    module: atom
  }

  defmacro __using__(_opts) do
    quote do
      require Logger
      require Chaperon.Scenario
      require Chaperon.Session
      import  Chaperon.Scenario
      import  Chaperon.Timing
      import  Chaperon.Session

      def start_link(config) do
        with {:ok, session} <- config |> new_session |> init do
          Scenario.Task.start_link session
        end
      end

      def new_session(config) do
        %Chaperon.Session{
          scenario: __MODULE__,
          config: config
        }
      end
    end
  end

  require Logger
  alias Chaperon.Session

  def execute(scenario_mod, config) do
    scenario = %Chaperon.Scenario{module: scenario_mod}
    session = %Session{
      id: "#{scenario_mod} #{UUID.uuid4}",
      scenario: scenario,
      config: config
    }

    {:ok, session} = session |> scenario_mod.init

    session =
      case config[:delay] do
        nil ->
          session

        duration ->
          session
          |> Session.delay(duration)
      end
      |> scenario_mod.run

    session.async_tasks
    |> Enum.reduce(session, fn {k, v}, acc ->
      acc |> Session.await(k, v)
    end)
    |> add_histogram_metrics
  end

  def add_histogram_metrics(session) do
    histograms = session |> record_metrics

    hist_vals = for {k, hist} <- histograms do
      {k, %{
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
        {:percentile, 99999} => :hdr_histogram.percentile(hist, 99.999),
        total_count: :hdr_histogram.get_total_count(hist)
      }}
    end
    |> Enum.into(%{})

    put_in session.metrics, hist_vals
  end

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

  def record_metric(_hist, []), do: :ok
  def record_metric(hist, [v | vals]) do
    record_metric(hist, v)
    record_metric(hist, vals)
  end

  def record_metric(hist, {:async, _name, val}) when is_number(val) do
    record_metric(hist, val)
  end

  def record_metric(hist, val) when is_number(val) do
    :hdr_histogram.record(hist, val)
  end
end
