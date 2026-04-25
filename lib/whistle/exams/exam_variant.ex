defmodule Whistle.Exams.ExamVariant do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_course_types ~w(F J G)
  @valid_statuses ~w(draft enabled disabled)

  schema "exam_variants" do
    field :name, :string
    field :course_type, :string
    field :status, :string, default: "draft"
    field :duration_seconds, :integer
    field :l1_threshold, :integer
    field :l2_threshold, :integer
    field :l3_threshold, :integer
    field :pass_threshold, :integer

    has_many :variant_questions, Whistle.Exams.ExamVariantQuestion,
      foreign_key: :exam_variant_id,
      preload_order: [asc: :position]

    has_many :questions, through: [:variant_questions, :question]

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def valid_course_types, do: @valid_course_types
  def valid_statuses, do: @valid_statuses

  @doc false
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [
      :name,
      :course_type,
      :status,
      :duration_seconds,
      :l1_threshold,
      :l2_threshold,
      :l3_threshold,
      :pass_threshold
    ])
    |> update_change(:name, fn
      name when is_binary(name) -> String.trim(name)
      name -> name
    end)
    |> validate_required([:name, :course_type, :status, :duration_seconds])
    |> validate_inclusion(:course_type, @valid_course_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_thresholds()
    |> unique_constraint([:name, :course_type])
    |> check_constraint(:course_type, name: :exam_variants_course_type_check)
    |> check_constraint(:status, name: :exam_variants_status_check)
  end

  defp validate_thresholds(changeset) do
    course_type = get_field(changeset, :course_type)
    status = get_field(changeset, :status)

    case {course_type, status} do
      {"F", "enabled"} ->
        changeset
        |> validate_required([:l1_threshold, :l2_threshold, :l3_threshold])
        |> validate_number(:l1_threshold, greater_than_or_equal_to: 0)
        |> validate_number(:l2_threshold, greater_than_or_equal_to: 0)
        |> validate_number(:l3_threshold, greater_than_or_equal_to: 0)
        |> validate_f_threshold_order()

      {"G", "enabled"} ->
        changeset
        |> validate_required([:pass_threshold])
        |> validate_number(:pass_threshold, greater_than_or_equal_to: 0)

      {"F", _} ->
        changeset
        |> validate_number(:l1_threshold, greater_than_or_equal_to: 0)
        |> validate_number(:l2_threshold, greater_than_or_equal_to: 0)
        |> validate_number(:l3_threshold, greater_than_or_equal_to: 0)
        |> validate_f_threshold_order()

      {"G", _} ->
        validate_number(changeset, :pass_threshold, greater_than_or_equal_to: 0)

      _ ->
        changeset
    end
  end

  defp validate_f_threshold_order(changeset) do
    l1 = get_field(changeset, :l1_threshold)
    l2 = get_field(changeset, :l2_threshold)
    l3 = get_field(changeset, :l3_threshold)

    cond do
      is_nil(l1) or is_nil(l2) or is_nil(l3) ->
        changeset

      is_integer(l1) and is_integer(l2) and is_integer(l3) and l1 >= l2 and l2 >= l3 ->
        changeset

      true ->
        add_error(changeset, :l1_threshold, "muss mindestens so hoch wie L2 und L3 sein")
    end
  end
end
