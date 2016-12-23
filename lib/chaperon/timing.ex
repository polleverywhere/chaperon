defmodule Chaperon.Timing do
  @type duration :: non_neg_integer | float
  @type time_unit :: :seconds | :milli_seconds | :micro_seconds | :nano_seconds

  @second 1000
  @minute @second * 60
  @hour   @minute * 60
  @day    @hour * 24
  @week   @day * 7

  @spec seconds(duration) :: duration
  def seconds(num), do: round(num * @second)

  @spec minutes(duration) :: duration
  def minutes(num), do: round(num * @minute)

  @spec hours(duration) :: duration
  def hours(num), do: round(num * @hour)

  @spec days(duration) :: duration
  def days(num), do: round(num * @day)

  @spec weeks(duration) :: duration
  def weeks(num), do: round(num * @week)

  @spec timestamp(time_unit) :: non_neg_integer
  def timestamp(unit \\ :milli_seconds) do
    :os.system_time(unit)
  end
end
