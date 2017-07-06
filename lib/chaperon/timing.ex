defmodule Chaperon.Timing do
  @moduledoc """
  Timing related helper functions and type definitions used within `Chaperon`.
  """

  @type duration_number :: non_neg_integer | float | Range.t
  @type duration :: duration_number | {:random, duration_number}
  @type time_unit :: :seconds | :milli_seconds | :micro_seconds | :nano_seconds

  @second 1000
  @minute @second * 60
  @hour   @minute * 60
  @day    @hour * 24
  @week   @day * 7

  @doc """
  Returns the correct amount of milliseconds for a given amount of seconds.
  """
  @spec seconds(duration) :: non_neg_integer
  def seconds(%Range{first: a, last: b}),
    do: round(:rand.uniform(b - a) + a) * @second
  def seconds(num),
    do: round(num * @second)

  @doc """
  Returns the correct amount of milliseconds for a given amount of minutes.
  """
  @spec minutes(duration) :: non_neg_integer
  def minutes(%Range{first: a, last: b}),
    do: round(:rand.uniform(b - a) + a) * @minute
  def minutes(num),
    do: round(num * @minute)

  @doc """
  Returns the correct amount of milliseconds for a given amount of hours.
  """
  @spec hours(duration) :: non_neg_integer
  def hours(%Range{first: a, last: b}),
    do: round(:rand.uniform(b - a) + a) * @hour
  def hours(num),
    do: round(num * @hour)

  @doc """
  Returns the correct amount of milliseconds for a given amount of days.
  """
  @spec days(duration) :: non_neg_integer
  def days(%Range{first: a, last: b}),
    do: round(:rand.uniform(b - a) + a) * @day
  def days(num), do: round(num * @day)

  @doc """
  Returns the correct amount of milliseconds for a given amount of weeks.
  """
  @spec weeks(duration) :: non_neg_integer
  def weeks(%Range{first: a, last: b}),
    do: round(:rand.uniform(b - a) + a) * @week
  def weeks(num),
    do: round(num * @week)

  @doc """
  Returns a timestamp with the given time unit.
  """
  @spec timestamp(time_unit) :: non_neg_integer
  def timestamp(unit \\ :milli_seconds) do
    :os.system_time(unit)
  end
end
