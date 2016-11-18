defmodule Canary.Timing do
  @second 1000
  @minute @second * 60
  @hour   @minute * 60
  @day    @hour * 24
  @week   @day * 7

  def seconds(num), do: num * @second
  def minutes(num), do: num * @minute
  def hours(num), do: num * @hour
  def days(num), do: num * @day
  def weeks(num), do: num * @week
end
