defmodule Chaperon.Export.S3 do
  @moduledoc """
  CSV metrics export module.
  """

  require Logger

  @behaviour Chaperon.Exporter

  @doc """
  Encodes metrics of given `session` into CSV format.
  """
  def encode(session, options \\ []) do
    nested_exporter(options).encode(session, options)
  end

  def write_output(lt_mod, options, data, filename) do
    lt_name = Chaperon.LoadTest.name(lt_mod)
    Logger.info("Chaperon.Export.S3 | Writing output for #{lt_name} to #{filename}")
    {:ok, files} = nested_exporter(options).write_output(lt_mod, options, data, filename)

    :ok =
      files
      |> Task.async_stream(&upload_file/1, max_concurrency: 10)
      |> Stream.run()

    {:ok, files}
  end

  defp nested_exporter(options) do
    options
    |> Keyword.fetch!(:export)
  end

  def upload_file(src_path) do
    Logger.info("Chaperon.Export.S3 | Uploading file #{src_path} to S3 bucket: #{s3_bucket()}")

    ExAws.S3.put_object(s3_bucket(), dest_path(src_path), File.read!(src_path))
    |> ExAws.request!()
  end

  def dest_path(src_path) do
    src_path
  end

  def s3_bucket() do
    case System.get_env("S3_BUCKET") do
      nil ->
        Application.get_env(:chaperon, __MODULE__)
        |> Keyword.fetch!(:bucket)

      bucket when is_binary(bucket) ->
        bucket
    end
  end
end
