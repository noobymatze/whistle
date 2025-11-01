# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Whistle is a Phoenix LiveView application for managing referee course
registrations. The system handles associations, clubs, seasons, courses, and
user registrations with authentication.

## Development Commands

### Setup and Dependencies
- `mix setup` - Complete project setup (deps, database, assets)
- `mix deps.get` - Install dependencies
- `mix phx.server` - Start Phoenix server (localhost:4000)
- `iex -S mix phx.server` - Start server in interactive Elixir shell

### Database Management
- `mix ecto.setup` - Create database, run migrations, seed data
- `mix ecto.reset` - Drop and recreate database
- `mix ecto.create` - Create database
- `mix ecto.migrate` - Run migrations
- `mix ecto.rollback` - Rollback migrations

### Testing
- `mix test` - Run all tests (creates test DB, runs migrations)
- `mix test --failed` - Run only failed tests
- `mix test test/path/to/specific_test.exs` - Run specific test file

### Assets
- `mix assets.setup` - Install Tailwind and esbuild
- `mix assets.build` - Build CSS and JS assets
- `mix assets.deploy` - Build and minify assets for production

### Database Services
- `docker-compose up -d` - Start PostgreSQL databases

## Architecture

### Core Domain Structure
- **Accounts**: User authentication and management
- **Associations**: Sports associations
- **Clubs**: Sports clubs belonging to associations
- **Seasons**: Registration periods with start/end dates
- **Courses**: Available courses for registration
- **Registrations**: User course registrations

### Key Components
- **LiveView**: `registration_live.ex` - Real-time registration interface with PubSub
- **Authentication**: Built-in Phoenix authentication with user sessions
- **Database**: PostgreSQL with comprehensive migrations
- **Views**: Course view aggregates participant counts

### Authentication Flow
1. User registration/login required
2. Club selection required before accessing main features
3. Three-tier authorization: unauthenticated → authenticated → club-selected

### Registration System
- Real-time updates via Phoenix PubSub
- Registration periods controlled by seasons
- Course capacity tracking with live participant counts
- Form validation and error handling

## Development Notes

### Database Configuration
- Development DB: `ref` database on port 5437
- Test DB: `ref_test` database on port 5438
- Credentials: user `ref`, password `sql`

### File Structure
- `lib/whistle/` - Domain contexts and schemas
- `lib/whistle_web/` - Web layer (controllers, views, LiveView)
- `priv/repo/migrations/` - Database migrations
- `setup/` - SQL seed files for initial data
- `test/` - Test files with fixtures

### Key Files
- `lib/whistle_web/router.ex` - Route definitions with authentication pipelines
- `lib/whistle_web/live/registration_live.ex` - Main registration LiveView
- `lib/whistle/courses/course_view.ex` - Database view for course data
- `priv/repo/migrations/` - Database schema evolution

## Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs<%= if live? do %> and `live_session` scopes<% end %>:
  - A plug `:fetch_<%= scope_config.scope.assign_key %>_for_<%= schema.singular %>` that is included in the default browser pipeline
  - A plug `:require_authenticated_<%= schema.singular %>` that redirects to the log in page when the <%= schema.singular %> is not authenticated<%= if live? do %>
  - A `live_session :current_<%= schema.singular %>` scope - for routes that need the current <%= schema.singular %> but don't require authentication, similar to `:fetch_<%= scope_config.scope.assign_key %>_for_<%= schema.singular %>`
  - A `live_session :require_authenticated_<%= schema.singular %>` scope - for routes that require authentication, similar to the plug with the same name<% end %>
  - In both cases, a `@<%= scope_config.scope.assign_key %>` is assigned to the Plug connection<%= if live? do %> and LiveView socket<% end %>
  - A plug `redirect_if_<%= schema.singular %>_is_authenticated` that redirects to a default path in case the <%= schema.singular %> is authenticated - useful for a registration page that should only be shown to unauthenticated <%= schema.plural %>
- **Always let the user know in which router scopes<%= if live? do%>, `live_session`,<% end %> and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `<%= scope_config.scope.assign_key %>` assign - it **does not assign a `current_<%= schema.singular %>` assign**
- Always pass the assign `<%= scope_config.scope.assign_key %>` to context modules as first argument. When performing queries, use `<%= scope_config.scope.assign_key %>.<%= schema.singular %>` to filter the query results
- To derive/access `current_<%= schema.singular %>` in templates, **always use the `@<%= scope_config.scope.assign_key %>.<%= schema.singular %>`**, never use **`@current_<%= schema.singular %>`** in templates<%= if live? do %> or LiveViews
- **Never** duplicate `live_session` names. A `live_session :current_<%= schema.singular %>` can only be defined __once__ in the router, so all routes for the `live_session :current_<%= schema.singular %>`  must be grouped in a single block<% end %>
- Anytime you hit `<%= scope_config.scope.assign_key %>` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug<%= if live? do %> and `live_session`<% end %> as described below**

### Routes that require authentication

<%= if live? do %>LiveViews that require login should **always be placed inside the __existing__ `live_session :require_authenticated_<%= schema.singular %>` block**:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_<%= schema.singular %>]

      live_session :require_authenticated_<%= schema.singular %>,
        on_mount: [{<%= inspect auth_module %>, :require_authenticated}] do
        # phx.gen.auth generated routes
        live "/<%= schema.plural %>/settings", <%= inspect schema.alias %>Live.Settings, :edit
        live "/<%= schema.plural %>/settings/confirm-email/:token", <%= inspect schema.alias %>Live.Settings, :confirm_email
        # our own routes that require logged in <%= schema.singular %>
        live "/", MyLiveThatRequiresAuth, :index
      end
    end

<% end %>Controller routes must be placed in a scope that sets the `:require_authenticated_<%= schema.singular %>` plug:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_<%= schema.singular %>]

      get "/", MyControllerThatRequiresAuth, :index
    end

### Routes that work with or without authentication

<%= if live? do %>LiveViews that can work with or without authentication, **always use the __existing__ `:current_<%= schema.singular %>` scope**, ie:

    scope "/", MyAppWeb do
      pipe_through [:browser]

      live_session :current_<%= schema.singular %>,
        on_mount: [{<%= inspect auth_module %>, :mount_<%= scope_config.scope.assign_key %>}] do
        # our own routes that work with or without authentication
        live "/", PublicLive
      end
    end

<% end %>Controllers automatically have the `<%= scope_config.scope.assign_key %>` available if they use the `:browser` pipeline.