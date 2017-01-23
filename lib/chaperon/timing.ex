defmodule Chaperon.Timing do
  @moduledoc """
  Timing related helper functions and type definitions used within `Chaperon`.
  """

  @type duration :: non_neg_integer | float
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
  def seconds(num), do: round(num * @second)


  @doc """
  Returns the correct amount of milliseconds for a given amount of minutes.
  """
  @spec minutes(duration) :: non_neg_integer
  def minutes(num), do: round(num * @minute)


  @doc """
  Returns the correct amount of milliseconds for a given amount of hours.
  """
  @spec hours(duration) :: non_neg_integer
  def hours(num), do: round(num * @hour)

  @doc """
  Returns the correct amount of milliseconds for a given amount of days.
  """
  @spec days(duration) :: non_neg_integer
  def days(num), do: round(num * @day)

  @doc """
  Returns the correct amount of milliseconds for a given amount of weeks.
  """
  @spec weeks(duration) :: non_neg_integer
  def weeks(num), do: round(num * @week)


  @doc """
  Returns a timestamp with the given time unit.
  """
  @spec timestamp(time_unit) :: non_neg_integer
  def timestamp(unit \\ :milli_seconds) do
    :os.system_time(unit)
  end
end
