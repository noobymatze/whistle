defmodule WhistleWeb.AdminHTML do
  use WhistleWeb, :html

  import WhistleWeb.RoleComponents

  embed_templates "admin_html/*"

  def role_badge_class(role) do
    case role do
      "SUPER_ADMIN" -> "bg-purple-100 text-purple-800"
      "ADMIN" -> "bg-red-100 text-red-800"
      "CLUB_ADMIN" -> "bg-blue-100 text-blue-800"
      "INSTRUCTOR" -> "bg-green-100 text-green-800"
      "USER" -> "bg-gray-100 text-gray-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
