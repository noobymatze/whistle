defmodule Whistle.Timezone do
  @moduledoc """
  Handles timezone conversions for the application.

  All timestamps are stored in UTC in the database, but displayed
  in the configured local timezone (Europe/Berlin by default).
  """

  @doc """
  Gets the configured local timezone for the application.
  Defaults to "Europe/Berlin" if not configured.
  """
  def local_timezone do
    Application.get_env(:whistle, :local_timezone, "Europe/Berlin")
  end

  @doc """
  Converts a UTC DateTime to the local timezone.

  ## Examples

      iex> utc_datetime = ~U[2024-01-15 12:00:00Z]
      iex> Whistle.Timezone.to_local(utc_datetime)
      #DateTime<2024-01-15 13:00:00+01:00 CET Europe/Berlin>
  """
  def to_local(%DateTime{} = datetime) do
    DateTime.shift_zone!(datetime, local_timezone())
  end

  def to_local(nil), do: nil

  @doc """
  Converts a local timezone DateTime to UTC.

  ## Examples

      iex> local_datetime = DateTime.new!(~D[2024-01-15], ~T[13:00:00], "Europe/Berlin")
      iex> Whistle.Timezone.to_utc(local_datetime)
      #DateTime<2024-01-15 12:00:00Z>
  """
  def to_utc(%DateTime{} = datetime) do
    DateTime.shift_zone!(datetime, "Etc/UTC")
  end

  def to_utc(nil), do: nil

  @doc """
  Creates a DateTime in the local timezone from a Date at the start of day (00:00:00).

  ## Examples

      iex> date = ~D[2024-01-15]
      iex> Whistle.Timezone.date_to_local_datetime(date)
      #DateTime<2024-01-15 00:00:00+01:00 CET Europe/Berlin>
  """
  def date_to_local_datetime(%Date{} = date) do
    DateTime.new!(date, ~T[00:00:00], local_timezone())
  end

  def date_to_local_datetime(nil), do: nil

  @doc """
  Creates a DateTime in the local timezone from a Date at the end of day (23:59:59).

  ## Examples

      iex> date = ~D[2024-01-15]
      iex> Whistle.Timezone.date_to_local_datetime_end_of_day(date)
      #DateTime<2024-01-15 23:59:59+01:00 CET Europe/Berlin>
  """
  def date_to_local_datetime_end_of_day(%Date{} = date) do
    DateTime.new!(date, ~T[23:59:59], local_timezone())
  end

  def date_to_local_datetime_end_of_day(nil), do: nil

  @doc """
  Formats a DateTime in the local timezone using the given format string.

  ## Examples

      iex> utc_datetime = ~U[2024-01-15 12:00:00Z]
      iex> Whistle.Timezone.format_local(utc_datetime, "%d.%m.%Y %H:%M")
      "15.01.2024 13:00"
  """
  def format_local(%DateTime{} = datetime, format) do
    datetime
    |> to_local()
    |> Calendar.strftime(format)
  end

  def format_local(nil, _format), do: ""

  @doc """
  Returns the current DateTime in the local timezone.

  ## Examples

      iex> Whistle.Timezone.now_local()
      #DateTime<...>
  """
  def now_local do
    DateTime.now!(local_timezone())
  end

  @doc """
  Returns today's date in the local timezone.

  ## Examples

      iex> Whistle.Timezone.today_local()
      ~D[2024-01-15]
  """
  def today_local do
    now_local() |> DateTime.to_date()
  end
end
