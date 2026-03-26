defmodule Whistle.AssociationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Whistle.Associations` context.
  """

  @doc """
  Generate a association.
  """
  def association_fixture(attrs \\ %{}) do
    {:ok, association} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Whistle.Associations.create_association()

    association
  end
end
