if Application.get_env(:chaperon, Chaperon.Export.InfluxDB, false) do
  defmodule Chaperon.Export.InfluxDB do
    @moduledoc """
    InfluxDB metric export module.
    """

    defmodule LoadTestMeasurement do
      @moduledoc false

      use Instream.Series
      alias Chaperon.Scenario.Metrics
      alias Chaperon.Util

      series do
        measurement("load_test")

        tag(:tag)
        tag(:action)
        tag(:session)
        tag(:load_test)

        field(:duration)
        field(:total_count)
        field(:max)
        field(:mean)
        field(:min)

        for p <- Metrics.percentiles() do
          field(Util.percentile_name(p))
        end
      end
    end

    @behaviour Chaperon.Exporter

    use Instream.Connection, otp_app: :chaperon
    alias Chaperon.Util
    alias __MODULE__.LoadTestMeasurement
    require Logger

    def write_output(lt_mod, _runtime_config, data, _) do
      Logger.info("Writing data for #{Chaperon.LoadTest.name(lt_mod)} to InfluxDB")

      for d <- data do
        :ok = __MODULE__.write(d)
      end

      :ok
    end

    @doc """
    Sends metrics of given `session` to InfluxDB in `LoadTestMeasurement` format.
    """
    def encode(session, opts \\ []) do
      data =
        session.metrics
        |> Enum.flat_map(fn
          {{:call, {mod, func}}, vals} ->
            mod_name = Util.shortened_module_name(mod)
            encode_runs(vals, "call(#{mod_name}.#{func})", opts)

          {{action, url}, vals} ->
            encode_runs(vals, "#{action}(#{url})", opts)

          {action, vals} ->
            encode_runs(vals, "#{action}", opts)
        end)

      {:ok, data}
    end

    def encode_runs(runs, action_name, opts) when is_list(runs) do
      runs
      |> Enum.map(&encode_run(&1, action_name, opts))
    end

    def encode_runs(run, action_name, opts) do
      [encode_run(run, action_name, opts)]
    end

    def encode_run(vals, action_name, opts) do
      session_name = vals[:session_name]
      data = %LoadTestMeasurement{}

      %{
        data
        | tags: %{
            data.tags
            | tag: opts[:tag],
              session: session_name,
              action: action_name,
              load_test: opts[:load_test]
          },
          fields: Map.merge(data.fields, measurement_fields(vals, opts))
      }
    end

    defp measurement_fields(vals, opts) do
      vals
      |> percentile_fields
      |> Map.merge(%{
        duration: opts[:duration],
        total_count: vals[:total_count],
        max: vals[:max],
        mean: vals[:mean],
        min: vals[:min]
      })
    end

    defp percentile_fields(vals) do
      Chaperon.Scenario.Metrics.percentiles()
      |> Enum.map(fn p ->
        {Util.percentile_name(p), vals[{:percentile, p}]}
      end)
      |> Enum.into(%{})
    end
  end
end
