defmodule ChaperonTest do
  use ExUnit.Case
  doctest Chaperon
  alias Chaperon.Export

  test "returns the right exporter implementation module" do
    assert Chaperon.exporter([]) == {Export.CSV, []}
    assert Chaperon.exporter(export: Export.JSON) == {Export.JSON, []}

    assert Chaperon.exporter(export: {Export.S3, Export.JSON}) ==
             {Export.S3, [export: Export.JSON]}
  end
end
