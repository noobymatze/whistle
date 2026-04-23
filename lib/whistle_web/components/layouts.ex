defmodule WhistleWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use WhistleWeb, :html

  alias Whistle.Accounts.Role

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :inner_content, :any, default: nil

  slot :inner_block

  def app(assigns) do
    ~H"""
    <%= if @current_user do %>
      <div
        id="app-shell"
        data-mobile-menu
        data-mobile-menu-open="false"
        class="relative min-h-screen bg-base-200/45 text-base-content"
      >
        <div class="relative flex min-h-screen">
          <button
            type="button"
            aria-label="Navigation schließen"
            data-mobile-menu-close
            class="fixed inset-0 z-40 bg-slate-950/45 opacity-0 pointer-events-none backdrop-blur-sm transition duration-300 md:hidden [[data-mobile-menu-open=true]_&]:opacity-100 [[data-mobile-menu-open=true]_&]:pointer-events-auto"
          >
          </button>

          <aside
            id="main-navigation"
            data-mobile-menu-panel
            aria-hidden="true"
            class="fixed inset-y-0 left-0 z-50 flex w-[min(16.5rem,calc(100vw-1.5rem))] -translate-x-full border-r border-base-300/70 bg-base-100/96 transition-transform duration-300 ease-out md:sticky md:top-0 md:h-screen md:w-64 md:shrink-0 md:translate-x-0 [[data-mobile-menu-open=true]_&]:translate-x-0"
          >
            <div class="flex h-full w-full flex-col overflow-hidden">
              <div class="flex items-center justify-end border-b border-base-300/70 px-4 py-4 md:hidden">
                <button
                  type="button"
                  aria-label="Navigation schließen"
                  data-mobile-menu-close
                  class="inline-flex size-10 items-center justify-center rounded-2xl border border-base-300/80 bg-base-100 text-base-content/60 transition hover:border-base-300 hover:text-base-content md:hidden"
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </div>

              <div class="border-b border-base-300/70 px-5 pb-4 pt-5">
                <a href={~p"/"} class="block">
                  <span class="min-w-0">
                    <span class="block truncate text-base font-semibold text-base-content">
                      Nordref
                    </span>
                    <span class="block text-[0.68rem] font-medium uppercase tracking-[0.22em] text-base-content/42">
                      Kursverwaltung
                    </span>
                  </span>
                </a>
              </div>

              <nav class="flex-1 space-y-6 overflow-y-auto px-4 py-5">
                <div class="space-y-1">
                  <p class="px-3 text-[0.68rem] font-semibold uppercase text-base-content/38">
                    Mein Bereich
                  </p>
                  <.nav_item
                    href={~p"/"}
                    icon="hero-home"
                    label="Kursanmeldung"
                    tone={:emerald}
                    active={path_active?(@current_path, {:exact, "/"})}
                  />
                  <.nav_item
                    href={~p"/my-courses"}
                    icon="hero-academic-cap"
                    label="Meine Kurse"
                    tone={:blue}
                    active={path_active?(@current_path, "/my-courses")}
                  />
                  <.nav_item
                    href={~p"/my-exams"}
                    icon="hero-clipboard-document-list"
                    label="Meine Tests"
                    tone={:blue}
                    active={path_active?(@current_path, "/my-exams")}
                  />
                </div>

                <div
                  :if={Role.can_access_course_area?(@current_user)}
                  class="space-y-1"
                >
                  <p class="px-3 text-[0.68rem] font-semibold uppercase text-base-content/38">
                    Kursverwaltung
                  </p>
                  <.nav_item
                    href={~p"/admin/courses"}
                    icon="hero-rectangle-stack"
                    label="Kurse"
                    tone={:blue}
                    active={path_active?(@current_path, ["/admin/courses", "/admin/exams"])}
                  />
                  <.nav_item
                    href={~p"/admin/questions"}
                    icon="hero-question-mark-circle"
                    label="Fragen"
                    tone={:violet}
                    active={path_active?(@current_path, "/admin/questions")}
                  />
                </div>

                <div
                  :if={Role.can_access_club_area?(@current_user)}
                  class="space-y-1"
                >
                  <p class="px-3 text-[0.68rem] font-semibold uppercase text-base-content/38">
                    Vereinsverwaltung
                  </p>
                  <.nav_item
                    href={~p"/admin/registrations"}
                    icon="hero-clipboard-document-list"
                    label="Anmeldungen"
                    tone={:emerald}
                    active={path_active?(@current_path, "/admin/registrations")}
                  />
                  <.nav_item
                    href={~p"/admin/users"}
                    icon="hero-users"
                    label="Benutzer"
                    tone={:violet}
                    active={path_active?(@current_path, "/admin/users")}
                  />
                </div>

                <div
                  :if={Role.can_access_global_area?(@current_user)}
                  class="space-y-1"
                >
                  <p class="px-3 text-[0.68rem] font-semibold uppercase text-base-content/38">
                    Systemverwaltung
                  </p>
                  <.nav_item
                    href={~p"/admin/seasons"}
                    icon="hero-calendar"
                    label="Saisons"
                    tone={:amber}
                    active={path_active?(@current_path, "/admin/seasons")}
                  />
                  <.nav_item
                    href={~p"/admin/clubs"}
                    icon="hero-building-office"
                    label="Vereine"
                    tone={:emerald}
                    active={path_active?(@current_path, "/admin/clubs")}
                  />
                  <.nav_item
                    href={~p"/admin/associations"}
                    icon="hero-building-library"
                    label="Verbände"
                    tone={:blue}
                    active={path_active?(@current_path, "/admin/associations")}
                  />
                  <.nav_item
                    :if={Role.super_admin?(@current_user)}
                    href={~p"/admin/jobs"}
                    icon="hero-server-stack"
                    label="Jobs"
                    tone={:violet}
                    active={path_active?(@current_path, "/admin/jobs")}
                  />
                </div>
              </nav>

              <div class="shrink-0 space-y-3 border-t border-base-300/70 px-4 py-4">
                <div class="flex justify-center">
                  <.theme_toggle />
                </div>

                <div class="rounded-[1.15rem] border border-base-300/70 bg-base-200/70 p-2.5 shadow-sm">
                  <div class="flex items-center gap-2.5">
                    <span class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-base-100 ring-1 ring-base-300/80">
                      <.icon name="hero-user-circle" class="size-5.5 text-base-content/55" />
                    </span>
                    <div class="min-w-0 flex-1 overflow-hidden">
                      <p
                        class="truncate text-xs font-semibold leading-tight"
                        title={@current_user.username}
                      >
                        {@current_user.username}
                      </p>
                      <p class="truncate text-[0.7rem] leading-tight text-base-content/55">
                        {role_label(@current_user.role)}
                      </p>
                      <%= if @current_user.license_level do %>
                        <p class="truncate text-[0.7rem] leading-tight text-base-content/55">
                          Lizenzstufe: {@current_user.license_level}
                        </p>
                      <% end %>
                      <%= if @current_user.license_number do %>
                        <p class="truncate text-[0.7rem] leading-tight text-base-content/55">
                          Nr.: {@current_user.license_number}
                        </p>
                      <% end %>
                    </div>
                    <.link
                      href={~p"/users/log_out"}
                      method="delete"
                      class="inline-flex size-8.5 items-center justify-center rounded-xl border border-base-300/80 bg-base-100 text-base-content/65 transition hover:border-base-300 hover:text-base-content"
                      title="Abmelden"
                    >
                      <.icon name="hero-arrow-right-start-on-rectangle" class="size-3.5" />
                    </.link>
                  </div>
                </div>
              </div>
            </div>
          </aside>

          <div class="min-w-0 flex-1">
            <main class="px-4 py-5 sm:px-6 sm:py-6 lg:px-10">
              <div class="mb-4 flex items-center justify-between md:hidden">
                <button
                  type="button"
                  aria-controls="main-navigation"
                  aria-expanded="false"
                  data-mobile-menu-open
                  class="inline-flex size-11 shrink-0 items-center justify-center rounded-2xl border border-base-300/80 bg-base-100 text-base-content/65 transition hover:border-base-300 hover:text-base-content"
                >
                  <.icon name="hero-bars-3" class="size-5" />
                </button>

                <span class="min-w-0 flex-1 truncate px-3 text-right text-xs font-semibold text-base-content/70">
                  {@current_user.username}
                </span>
              </div>

              <div class="mx-auto w-full max-w-6xl space-y-4">
                <%= if @inner_block != [] do %>
                  {render_slot(@inner_block)}
                <% else %>
                  {@inner_content}
                <% end %>
              </div>
            </main>
          </div>
        </div>

        <.flash_group flash={@flash} />
      </div>
    <% else %>
      <div class="min-h-screen bg-base-200 text-base-content">
        <header class="px-4 pt-6 sm:px-6 lg:px-8">
          <div class="mx-auto flex max-w-sm items-center justify-between">
            <a
              href={~p"/"}
              class="text-sm font-semibold tracking-[0.2em] text-base-content/55 uppercase"
            >
              Nordref
            </a>
            <.theme_toggle />
          </div>
        </header>

        <main class="px-4 py-12 sm:px-6 lg:px-8">
          <div class="mx-auto max-w-sm rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm sm:p-8">
            <%= if @inner_block != [] do %>
              {render_slot(@inner_block)}
            <% else %>
              {@inner_content}
            <% end %>
          </div>
        </main>

        <.flash_group flash={@flash} />
      </div>
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :tone, :atom, default: :blue

  defp nav_item(assigns) do
    assigns = assign(assigns, :colors, color_classes(assigns.tone))

    ~H"""
    <.link
      href={@href}
      data-mobile-menu-close
      aria-current={if @active, do: "page", else: nil}
      class={[
        "group flex items-center gap-2.5 rounded-[0.95rem] px-3 py-2 text-[0.95rem] transition duration-200",
        if(@active,
          do: ["bg-base-200/85", @colors.soft],
          else: "text-base-content/72 hover:bg-base-200/60 hover:text-base-content"
        )
      ]}
    >
      <span class={[
        "flex size-5 shrink-0 items-center justify-center transition duration-200",
        if(@active,
          do: @colors.text,
          else: "text-base-content/46 group-hover:text-base-content/70"
        )
      ]}>
        <.icon
          name={@icon}
          class={[
            "size-[1.05rem] transition duration-200",
            if(@active, do: "opacity-100", else: "opacity-90")
          ]}
        />
      </span>

      <span class="min-w-0 flex-1">
        <span class={[
          "block truncate",
          if(@active, do: ["font-semibold", @colors.text], else: "font-medium")
        ]}>
          {@label}
        </span>
      </span>
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides a compact three-way theme selector based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="inline-flex items-center rounded-full border border-base-300/80 bg-base-200/75 p-0.75 shadow-sm">
      <button
        type="button"
        aria-label="Desktop-Design aktivieren"
        title="Desktop"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        class="inline-flex size-9 items-center justify-center rounded-full text-base-content shadow-sm transition hover:text-base-content/90 bg-base-100 [[data-theme=light]_&]:bg-transparent [[data-theme=light]_&]:shadow-none [[data-theme=dark]_&]:bg-transparent [[data-theme=dark]_&]:shadow-none"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
        <span class="sr-only">Desktop</span>
      </button>

      <button
        type="button"
        aria-label="Helles Design aktivieren"
        title="Light"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        class="inline-flex size-9 items-center justify-center rounded-full text-base-content/65 transition hover:text-base-content/90 [[data-theme=light]_&]:bg-base-100 [[data-theme=light]_&]:text-base-content [[data-theme=light]_&]:shadow-sm"
      >
        <.icon name="hero-sun-micro" class="size-4" />
        <span class="sr-only">Light</span>
      </button>

      <button
        type="button"
        aria-label="Dunkles Design aktivieren"
        title="Dark"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        class="inline-flex size-9 items-center justify-center rounded-full text-base-content/65 transition hover:text-base-content/90 [[data-theme=dark]_&]:bg-base-100 [[data-theme=dark]_&]:text-base-content [[data-theme=dark]_&]:shadow-sm"
      >
        <.icon name="hero-moon-micro" class="size-4" />
        <span class="sr-only">Dark</span>
      </button>
    </div>
    """
  end

  defp path_active?(nil, _matcher), do: false

  defp path_active?(current_path, matchers) when is_list(matchers) do
    Enum.any?(matchers, &path_active?(current_path, &1))
  end

  defp path_active?(current_path, {:exact, path}), do: current_path == path
  defp path_active?(current_path, path), do: String.starts_with?(current_path, path)

  defp role_label("SUPER_ADMIN"), do: "Superadmin"
  defp role_label("ADMIN"), do: "Administrator"
  defp role_label("CLUB_ADMIN"), do: "Vereinsadmin"
  defp role_label("INSTRUCTOR"), do: "Ausbilder"
  defp role_label("USER"), do: "Mitglied"
  defp role_label(_), do: "Benutzer"

  defp color_classes(:amber) do
    %{text: "text-amber-600 dark:text-amber-400", soft: "bg-amber-500/10", dot: "bg-amber-500"}
  end

  defp color_classes(:emerald) do
    %{
      text: "text-emerald-600 dark:text-emerald-400",
      soft: "bg-emerald-500/10",
      dot: "bg-emerald-500"
    }
  end

  defp color_classes(:violet) do
    %{
      text: "text-violet-600 dark:text-violet-400",
      soft: "bg-violet-500/10",
      dot: "bg-violet-500"
    }
  end

  defp color_classes(:blue) do
    %{text: "text-sky-600 dark:text-sky-400", soft: "bg-sky-500/10", dot: "bg-sky-500"}
  end
end
