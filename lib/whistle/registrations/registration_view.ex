defmodule Whistle.Registrations.RegistrationView do
  use Ecto.Schema

  @primary_key false
  schema "registrations_view" do
    field :organizer_id, :integer
    field :organizer_name, :string
    field :organizer_short_name, :string
    field :association_id, :integer
    field :association_name, :string
    field :user_id, :integer
    field :user_first_name, :string
    field :user_last_name, :string
    field :user_email, :string
    field :user_birthday, :date
    field :username, :string
    field :user_club_id, :integer
    field :registered_at, :utc_datetime
    field :registered_by, :integer
    field :unenrolled_by, :integer
    field :unenrolled_at, :utc_datetime
    field :course_id, :integer
    field :course_name, :string
    field :season_id, :integer
    field :course_date, :date
    field :year, :integer
    field :user_club_name, :string
    field :license_number, :integer
  end
end
