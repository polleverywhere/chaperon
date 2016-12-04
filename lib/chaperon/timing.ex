defmodule Chaperon.Timing do
  @type duration :: non_neg_integer

  @second 1000
  @minute @second * 60
  @hour   @minute * 60
  @day    @hour * 24
  @week   @day * 7

  @spec seconds(duration) :: duration
  def seconds(num), do: num * @second

  @spec minutes(duration) :: duration
  def minutes(num), do: num * @minute

  @spec hours(duration) :: duration
  def hours(num), do: num * @hour

  @spec days(duration) :: duration
  def days(num), do: num * @day

  @spec weeks(duration) :: duration
  def weeks(num), do: num * @week
end
