defmodule Whistle.Timezone do
  @moduledoc """
  Handles datetime operations for the application.

  All timestamps are stored as naive datetime in Europe/Berlin timezone.
  """

  def local_timezone, do: "Europe/Berlin"

  def format_local(%NaiveDateTime{} = naive_datetime, format) do
    Calendar.strftime(naive_datetime, format)
  end

  def format_local(nil, _format), do: ""

  def date_to_local_datetime(%Date{} = date) do
    NaiveDateTime.new!(date, ~T[00:00:00])
  end

  def date_to_local_datetime(nil), do: nil

  def date_to_local_datetime_end_of_day(%Date{} = date) do
    NaiveDateTime.new!(date, ~T[23:59:59])
  end

  def date_to_local_datetime_end_of_day(nil), do: nil

  def now_local do
    NaiveDateTime.local_now()
  end

  def today_local do
    Date.utc_today()
  end
end
