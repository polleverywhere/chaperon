defmodule Chaperon.Session.Logging do
  @moduledoc """
  Chaperon.Session log helper macros.
  """

  defmacro __using__(_opts) do
    quote do
      require Logger
      require Chaperon.Session.Logging
      import Chaperon.Session.Logging
    end
  end

  defmacro log_info(session, message) do
    quote do
      require Logger
      session = unquote(session)
      Logger.info("#{session.id} #{session.name} | #{unquote(message)} ")
      session
    end
  end

  defmacro log_debug(session, message) do
    quote do
      require Logger
      session = unquote(session)
      Logger.debug(fn -> "#{session.id} #{session.name} | #{unquote(message)} " end)
      session
    end
  end

  defmacro log_error(session, message) do
    quote do
      require Logger
      session = unquote(session)
      Logger.error("#{session.id} #{session.name} | #{unquote(message)} ")
      session
    end
  end

  defmacro log_error(session, message, reason) do
    quote do
      require Logger
      session = unquote(session)

      Logger.error(
        "#{session.id} #{session.name} | #{unquote(message)} #{inspect(unquote(reason))}"
      )

      session
    end
  end

  defmacro log_warn(session, message) do
    quote do
      require Logger
      session = unquote(session)
      Logger.warn("#{session.id} #{session.name} | #{unquote(message)} ")
      session
    end
  end
end
