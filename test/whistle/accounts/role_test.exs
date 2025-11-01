defmodule Whistle.Accounts.RoleTest do
  use ExUnit.Case, async: true

  alias Whistle.Accounts.Role

  describe "roles/0" do
    test "returns all valid roles" do
      assert Role.roles() == ["SUPER_ADMIN", "ADMIN", "CLUB_ADMIN", "INSTRUCTOR", "USER"]
    end
  end

  describe "default_role/0" do
    test "returns USER as default role" do
      assert Role.default_role() == "USER"
    end
  end

  describe "valid_role?/1" do
    test "returns true for valid roles" do
      assert Role.valid_role?("SUPER_ADMIN")
      assert Role.valid_role?("ADMIN")
      assert Role.valid_role?("CLUB_ADMIN")
      assert Role.valid_role?("INSTRUCTOR")
      assert Role.valid_role?("USER")
    end

    test "returns false for invalid roles" do
      refute Role.valid_role?("INVALID")
      refute Role.valid_role?("user")
      refute Role.valid_role?("")
      refute Role.valid_role?(nil)
    end
  end

  describe "role_level/1" do
    test "returns correct hierarchy levels" do
      assert Role.role_level("SUPER_ADMIN") == 0
      assert Role.role_level("ADMIN") == 1
      assert Role.role_level("CLUB_ADMIN") == 2
      assert Role.role_level("INSTRUCTOR") == 3
      assert Role.role_level("USER") == 4
    end

    test "returns 99 for invalid roles" do
      assert Role.role_level("INVALID") == 99
    end
  end

  describe "has_role?/2" do
    test "returns true when user has exact role" do
      user = %{role: "ADMIN"}
      assert Role.has_role?(user, "ADMIN")
    end

    test "returns false when user has different role" do
      user = %{role: "USER"}
      refute Role.has_role?(user, "ADMIN")
    end
  end

  describe "has_role_level?/2" do
    test "returns true when user has required role level or higher" do
      super_admin = %{role: "SUPER_ADMIN"}
      admin = %{role: "ADMIN"}
      _club_admin = %{role: "CLUB_ADMIN"}
      user = %{role: "USER"}

      # SUPER_ADMIN can access everything
      assert Role.has_role_level?(super_admin, "SUPER_ADMIN")
      assert Role.has_role_level?(super_admin, "ADMIN")
      assert Role.has_role_level?(super_admin, "CLUB_ADMIN")
      assert Role.has_role_level?(super_admin, "INSTRUCTOR")
      assert Role.has_role_level?(super_admin, "USER")

      # ADMIN can access ADMIN level and below
      refute Role.has_role_level?(admin, "SUPER_ADMIN")
      assert Role.has_role_level?(admin, "ADMIN")
      assert Role.has_role_level?(admin, "CLUB_ADMIN")
      assert Role.has_role_level?(admin, "INSTRUCTOR")
      assert Role.has_role_level?(admin, "USER")

      # USER can only access USER level
      refute Role.has_role_level?(user, "SUPER_ADMIN")
      refute Role.has_role_level?(user, "ADMIN")
      refute Role.has_role_level?(user, "CLUB_ADMIN")
      refute Role.has_role_level?(user, "INSTRUCTOR")
      assert Role.has_role_level?(user, "USER")
    end
  end

  describe "can_manage_user?/2" do
    test "higher role levels can manage lower role levels" do
      super_admin = %{role: "SUPER_ADMIN"}
      admin = %{role: "ADMIN"}
      club_admin = %{role: "CLUB_ADMIN"}
      instructor = %{role: "INSTRUCTOR"}
      user = %{role: "USER"}

      # SUPER_ADMIN can manage everyone except other SUPER_ADMINs
      refute Role.can_manage_user?(super_admin, super_admin)
      assert Role.can_manage_user?(super_admin, admin)
      assert Role.can_manage_user?(super_admin, club_admin)
      assert Role.can_manage_user?(super_admin, instructor)
      assert Role.can_manage_user?(super_admin, user)

      # ADMIN can manage everyone except SUPER_ADMIN and other ADMINs
      refute Role.can_manage_user?(admin, super_admin)
      refute Role.can_manage_user?(admin, admin)
      assert Role.can_manage_user?(admin, club_admin)
      assert Role.can_manage_user?(admin, instructor)
      assert Role.can_manage_user?(admin, user)

      # CLUB_ADMIN can manage INSTRUCTOR and USER
      refute Role.can_manage_user?(club_admin, super_admin)
      refute Role.can_manage_user?(club_admin, admin)
      refute Role.can_manage_user?(club_admin, club_admin)
      assert Role.can_manage_user?(club_admin, instructor)
      assert Role.can_manage_user?(club_admin, user)

      # INSTRUCTOR and USER cannot manage anyone
      refute Role.can_manage_user?(instructor, user)
      refute Role.can_manage_user?(user, user)
    end
  end

  describe "can_assign_role?/2" do
    test "super admin can assign any role" do
      super_admin = %{role: "SUPER_ADMIN"}

      assert Role.can_assign_role?(super_admin, "SUPER_ADMIN")
      assert Role.can_assign_role?(super_admin, "ADMIN")
      assert Role.can_assign_role?(super_admin, "CLUB_ADMIN")
      assert Role.can_assign_role?(super_admin, "INSTRUCTOR")
      assert Role.can_assign_role?(super_admin, "USER")
    end

    test "admin can assign any role except super admin" do
      admin = %{role: "ADMIN"}

      refute Role.can_assign_role?(admin, "SUPER_ADMIN")
      assert Role.can_assign_role?(admin, "ADMIN")
      assert Role.can_assign_role?(admin, "CLUB_ADMIN")
      assert Role.can_assign_role?(admin, "INSTRUCTOR")
      assert Role.can_assign_role?(admin, "USER")
    end

    test "club admin can assign limited roles" do
      club_admin = %{role: "CLUB_ADMIN"}

      refute Role.can_assign_role?(club_admin, "SUPER_ADMIN")
      refute Role.can_assign_role?(club_admin, "ADMIN")
      assert Role.can_assign_role?(club_admin, "CLUB_ADMIN")
      assert Role.can_assign_role?(club_admin, "INSTRUCTOR")
      assert Role.can_assign_role?(club_admin, "USER")
    end

    test "instructor and user cannot assign roles" do
      instructor = %{role: "INSTRUCTOR"}
      user = %{role: "USER"}

      refute Role.can_assign_role?(instructor, "USER")
      refute Role.can_assign_role?(user, "USER")
    end
  end

  describe "assignable_roles/1" do
    test "returns correct assignable roles for each role level" do
      super_admin = %{role: "SUPER_ADMIN"}
      admin = %{role: "ADMIN"}
      club_admin = %{role: "CLUB_ADMIN"}
      instructor = %{role: "INSTRUCTOR"}
      user = %{role: "USER"}

      assert Role.assignable_roles(super_admin) == [
               "SUPER_ADMIN",
               "ADMIN",
               "CLUB_ADMIN",
               "INSTRUCTOR",
               "USER"
             ]

      assert Role.assignable_roles(admin) == ["ADMIN", "CLUB_ADMIN", "INSTRUCTOR", "USER"]
      assert Role.assignable_roles(club_admin) == ["CLUB_ADMIN", "INSTRUCTOR", "USER"]
      assert Role.assignable_roles(instructor) == []
      assert Role.assignable_roles(user) == []
    end
  end

  describe "admin?/1" do
    test "returns true for admin roles" do
      assert Role.admin?(%{role: "SUPER_ADMIN"})
      assert Role.admin?(%{role: "ADMIN"})
      assert Role.admin?(%{role: "CLUB_ADMIN"})
    end

    test "returns false for non-admin roles" do
      refute Role.admin?(%{role: "INSTRUCTOR"})
      refute Role.admin?(%{role: "USER"})
    end
  end

  describe "super_admin?/1" do
    test "returns true only for super admin" do
      assert Role.super_admin?(%{role: "SUPER_ADMIN"})
      refute Role.super_admin?(%{role: "ADMIN"})
      refute Role.super_admin?(%{role: "CLUB_ADMIN"})
      refute Role.super_admin?(%{role: "INSTRUCTOR"})
      refute Role.super_admin?(%{role: "USER"})
    end
  end

  describe "full_admin?/1" do
    test "returns true for super admin and admin" do
      assert Role.full_admin?(%{role: "SUPER_ADMIN"})
      assert Role.full_admin?(%{role: "ADMIN"})
      refute Role.full_admin?(%{role: "CLUB_ADMIN"})
      refute Role.full_admin?(%{role: "INSTRUCTOR"})
      refute Role.full_admin?(%{role: "USER"})
    end
  end

  describe "can_access_admin?/1" do
    test "returns true for admin roles" do
      assert Role.can_access_admin?(%{role: "SUPER_ADMIN"})
      assert Role.can_access_admin?(%{role: "ADMIN"})
      assert Role.can_access_admin?(%{role: "CLUB_ADMIN"})
      refute Role.can_access_admin?(%{role: "INSTRUCTOR"})
      refute Role.can_access_admin?(%{role: "USER"})
    end
  end

  describe "can_manage_courses?/1" do
    test "returns true for roles that can manage courses" do
      assert Role.can_manage_courses?(%{role: "SUPER_ADMIN"})
      assert Role.can_manage_courses?(%{role: "ADMIN"})
      assert Role.can_manage_courses?(%{role: "CLUB_ADMIN"})
      assert Role.can_manage_courses?(%{role: "INSTRUCTOR"})
      refute Role.can_manage_courses?(%{role: "USER"})
    end
  end

  describe "can_view_all_users?/1" do
    test "returns true for full admin roles" do
      assert Role.can_view_all_users?(%{role: "SUPER_ADMIN"})
      assert Role.can_view_all_users?(%{role: "ADMIN"})
      refute Role.can_view_all_users?(%{role: "CLUB_ADMIN"})
      refute Role.can_view_all_users?(%{role: "INSTRUCTOR"})
      refute Role.can_view_all_users?(%{role: "USER"})
    end
  end

  describe "can_manage_club_users?/1" do
    test "returns true for admin roles" do
      assert Role.can_manage_club_users?(%{role: "SUPER_ADMIN"})
      assert Role.can_manage_club_users?(%{role: "ADMIN"})
      assert Role.can_manage_club_users?(%{role: "CLUB_ADMIN"})
      refute Role.can_manage_club_users?(%{role: "INSTRUCTOR"})
      refute Role.can_manage_club_users?(%{role: "USER"})
    end
  end

  describe "role_description/1" do
    test "returns human-readable descriptions" do
      assert Role.role_description("SUPER_ADMIN") == "Super Administrator"
      assert Role.role_description("ADMIN") == "Administrator"
      assert Role.role_description("CLUB_ADMIN") == "Club Administrator"
      assert Role.role_description("INSTRUCTOR") == "Instructor"
      assert Role.role_description("USER") == "User"
      assert Role.role_description("INVALID") == "Unknown"
    end
  end

  describe "role_options/0" do
    test "returns formatted options for forms" do
      options = Role.role_options()

      assert {"Super Administrator", "SUPER_ADMIN"} in options
      assert {"Administrator", "ADMIN"} in options
      assert {"Club Administrator", "CLUB_ADMIN"} in options
      assert {"Instructor", "INSTRUCTOR"} in options
      assert {"User", "USER"} in options
      assert length(options) == 5
    end
  end
end
