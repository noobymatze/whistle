defmodule WhistleWeb.ExamVariantLiveTest do
  use WhistleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Whistle.AccountsFixtures
  import Whistle.ExamsFixtures

  alias Whistle.Exams
  alias Whistle.Exams.ExamVariant
  alias Whistle.Repo

  defp log_in(conn, user) do
    token = Whistle.Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  defp instructor_fixture do
    user_fixture(%{role: "INSTRUCTOR"})
  end

  describe "form" do
    test "shows question assignments while creating a new variant", %{conn: conn} do
      question = question_with_choices_fixture("F")
      user = instructor_fixture()

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/admin/exam-variants/new")

      assert has_element?(view, "#exam-variant-form")
      assert has_element?(view, "#exam-variant-question-#{question.id}-selected")
      assert has_element?(view, "#exam-variant-question-#{question.id}-position")
    end

    test "saves a draft variant without thresholds or questions", %{conn: conn} do
      user = instructor_fixture()
      name = "Draft #{System.unique_integer([:positive])}"

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/admin/exam-variants/new")

      view
      |> form("#exam-variant-form", %{
        "exam_variant" => %{
          "name" => name,
          "course_type" => "F",
          "status" => "draft",
          "duration_seconds" => "1800",
          "l1_threshold" => "",
          "l2_threshold" => "",
          "l3_threshold" => "",
          "pass_threshold" => ""
        }
      })
      |> render_submit()

      variant = Repo.get_by!(ExamVariant, name: name)
      assert_patch(view, ~p"/admin/exam-variants/#{variant}/edit")
      assert variant.status == "draft"
      assert Exams.list_exam_variant_questions(variant) == []
    end

    test "shows validation errors for an enabled variant that is not ready", %{conn: conn} do
      user = instructor_fixture()
      name = "Enabled Invalid #{System.unique_integer([:positive])}"

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/admin/exam-variants/new")

      view
      |> form("#exam-variant-form", %{
        "exam_variant" => %{
          "name" => name,
          "course_type" => "F",
          "status" => "enabled",
          "duration_seconds" => "1800",
          "l1_threshold" => "",
          "l2_threshold" => "",
          "l3_threshold" => "",
          "pass_threshold" => ""
        }
      })
      |> render_submit()

      assert has_element?(view, "#exam-variant-error-summary")
      assert has_element?(view, "#exam-variant-error-summary li")
      refute Repo.get_by(ExamVariant, name: name)
    end

    test "saves an enabled variant with questions in one submit", %{conn: conn} do
      first = question_with_choices_fixture("F")
      second = question_with_choices_fixture("F")
      user = instructor_fixture()
      name = "Enabled #{System.unique_integer([:positive])}"

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/admin/exam-variants/new")

      view
      |> form("#exam-variant-form", %{
        "exam_variant" => %{
          "name" => name,
          "course_type" => "F",
          "status" => "enabled",
          "duration_seconds" => "1800",
          "l1_threshold" => "1",
          "l2_threshold" => "1",
          "l3_threshold" => "1",
          "pass_threshold" => ""
        },
        "variant_questions" => %{
          "#{first.id}" => %{"selected" => "true", "position" => "1"},
          "#{second.id}" => %{"selected" => "true", "position" => "2"}
        }
      })
      |> render_submit()

      variant = Repo.get_by!(ExamVariant, name: name)
      assert_patch(view, ~p"/admin/exam-variants/#{variant}/edit")
      assert variant.status == "enabled"

      assert Enum.map(Exams.list_exam_variant_questions(variant), &{&1.question_id, &1.position}) ==
               [{first.id, 1}, {second.id, 2}]
    end
  end
end
