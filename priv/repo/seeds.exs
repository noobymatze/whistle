# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Safe to re-run: each section checks for existing data before inserting.

alias Whistle.Repo
alias Whistle.Accounts.User
alias Whistle.Associations
alias Whistle.Clubs
alias Whistle.Seasons
alias Whistle.Courses
alias Whistle.Registrations
alias Whistle.Exams

import Ecto.Query

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

defmodule Seeds.Helpers do
  def create_user!(attrs) do
    existing = Repo.one(from u in User, where: u.username == ^attrs.username)

    if existing do
      existing
    else
      %User{}
      |> User.registration_changeset(Map.merge(attrs, %{password: "Testpasswort123!"}))
      |> Ecto.Changeset.put_change(:role, Map.get(attrs, :role, "USER"))
      |> Ecto.Changeset.put_change(
        :confirmed_at,
        NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      )
      |> Repo.insert!()
    end
  end
end

# ---------------------------------------------------------------------------
# 1. Associations
# ---------------------------------------------------------------------------

IO.puts("\n--- Verbände ---")

associations =
  [
    "Norddeutscher Fußball-Verband",
    "Hamburger Fußball-Verband",
    "Schleswig-Holsteinischer Fußball-Verband",
    "Bremer Fußball-Verband"
  ]
  |> Enum.map(fn name ->
    existing = Repo.one(from a in Whistle.Associations.Association, where: a.name == ^name)

    if existing do
      IO.puts("  Verband existiert bereits: #{name}")
      existing
    else
      {:ok, a} = Associations.create_association(%{name: name})
      IO.puts("  Erstellt: #{name}")
      a
    end
  end)

[nfv, hfv, shfv, bfv] = associations

# ---------------------------------------------------------------------------
# 2. Clubs
# ---------------------------------------------------------------------------

IO.puts("\n--- Vereine ---")

clubs_data = [
  {nfv.id, "Hamburger SV", "HSV"},
  {nfv.id, "FC St. Pauli", "FCSP"},
  {hfv.id, "Altona 93", "A93"},
  {hfv.id, "FC Teutonia 05", "FCT"},
  {hfv.id, "Eimsbütteler TV", "ETV"},
  {shfv.id, "Holstein Kiel", "KIE"},
  {shfv.id, "VfB Lübeck", "LÜB"},
  {bfv.id, "Werder Bremen II", "WER"},
  {bfv.id, "FC Oberneuland", "FCO"},
  {nfv.id, "Hannover 96 II", "H96"}
]

clubs =
  Enum.map(clubs_data, fn {assoc_id, name, short} ->
    existing = Repo.one(from c in Whistle.Clubs.Club, where: c.name == ^name)

    if existing do
      IO.puts("  Verein existiert bereits: #{name}")
      existing
    else
      {:ok, c} = Clubs.create_club(%{name: name, short_name: short, association_id: assoc_id})
      IO.puts("  Erstellt: #{name}")
      c
    end
  end)

[hsv, st_pauli, altona, teutonia, eimsbuettel, kiel, luebeck, werder, oberneuland, hannover] =
  clubs

# ---------------------------------------------------------------------------
# 3. Admin user
# ---------------------------------------------------------------------------

IO.puts("\n--- Benutzer ---")

admin =
  Seeds.Helpers.create_user!(%{
    username: "admin",
    email: "admin@nordref.de",
    first_name: "Admin",
    last_name: "Nordref",
    birthday: ~D[1980-01-01],
    club_id: hsv.id,
    role: "ADMIN"
  })

IO.puts("  Admin: #{admin.email}")

# ---------------------------------------------------------------------------
# 4. Regular users (participants for courses/exams)
# ---------------------------------------------------------------------------

users_data = [
  {"mueller_thomas", "thomas.mueller@example.de", "Thomas", "Müller", ~D[1990-03-15], hsv.id},
  {"schmidt_anna", "anna.schmidt@example.de", "Anna", "Schmidt", ~D[1988-07-22], st_pauli.id},
  {"weber_markus", "markus.weber@example.de", "Markus", "Weber", ~D[1995-11-05], altona.id},
  {"fischer_laura", "laura.fischer@example.de", "Laura", "Fischer", ~D[1992-04-30], teutonia.id},
  {"wagner_peter", "peter.wagner@example.de", "Peter", "Wagner", ~D[1985-09-12], eimsbuettel.id},
  {"becker_sabine", "sabine.becker@example.de", "Sabine", "Becker", ~D[1993-06-18], kiel.id},
  {"hoffmann_jan", "jan.hoffmann@example.de", "Jan", "Hoffmann", ~D[1997-02-28], luebeck.id},
  {"schulz_marie", "marie.schulz@example.de", "Marie", "Schulz", ~D[1991-08-09], werder.id},
  {"braun_felix", "felix.braun@example.de", "Felix", "Braun", ~D[1994-12-03], oberneuland.id},
  {"klein_nina", "nina.klein@example.de", "Nina", "Klein", ~D[1996-05-20], hannover.id},
  {"wolf_stefan", "stefan.wolf@example.de", "Stefan", "Wolf", ~D[1987-10-14], hsv.id},
  {"richter_claudia", "claudia.richter@example.de", "Claudia", "Richter", ~D[1989-01-25],
   st_pauli.id}
]

users =
  Enum.map(users_data, fn {username, email, first, last, birthday, club_id} ->
    u =
      Seeds.Helpers.create_user!(%{
        username: username,
        email: email,
        first_name: first,
        last_name: last,
        birthday: birthday,
        club_id: club_id
      })

    IO.puts("  Benutzer: #{first} #{last} (#{email})")
    u
  end)

[mueller, schmidt, weber, fischer, wagner, becker, hoffmann, schulz, braun, klein, wolf, richter] =
  users

# ---------------------------------------------------------------------------
# 5. Seasons
# ---------------------------------------------------------------------------

IO.puts("\n--- Saisons ---")

seasons_data = [
  {2024, ~D[2024-01-01], ~N[2023-10-01 00:00:00], ~N[2023-12-31 23:59:59]},
  {2025, ~D[2025-01-01], ~N[2024-10-01 00:00:00], ~N[2024-12-31 23:59:59]},
  {2026, ~D[2026-01-01], ~N[2025-10-01 00:00:00], ~N[2026-06-30 23:59:59]}
]

seasons =
  Enum.map(seasons_data, fn {year, start, reg_start, reg_end} ->
    existing = Repo.one(from s in Whistle.Seasons.Season, where: s.year == ^year, limit: 1)

    if existing do
      IO.puts("  Saison #{year} existiert bereits")
      existing
    else
      {:ok, s} =
        Seasons.create_season(%{
          year: year,
          start: start,
          start_registration: reg_start,
          end_registration: reg_end
        })

      IO.puts("  Erstellt: Saison #{year}")
      s
    end
  end)

[_season_2024, season_2025, season_2026] = seasons

# ---------------------------------------------------------------------------
# 6. Questions — realistic referee exam content
# ---------------------------------------------------------------------------

IO.puts("\n--- Fragen ---")

if Repo.aggregate(Whistle.Exams.Question, :count) == 0 do
  defmodule Seeds.Questions do
    def create!(attrs, course_types, choices) do
      {:ok, q} = Exams.create_question(attrs)

      Enum.each(choices, fn {body, is_correct, pos} ->
        Exams.create_question_choice(%{
          question_id: q.id,
          body_markdown: body,
          position: pos,
          is_correct: is_correct
        })
      end)

      Exams.set_question_course_types(q, course_types)
      q
    end
  end

  # --- F-course questions (Feldschiedsrichter Unihockey) ---

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Wie lange dauert eine reguläre Spielzeit im **Unihockey** (IFF-Regeln)?"
    },
    ["F"],
    [
      {"3 × 20 Minuten (reine Spielzeit)", true, 1},
      {"2 × 45 Minuten", false, 2},
      {"2 × 30 Minuten", false, 3},
      {"3 × 15 Minuten", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Wie viele Feldspieler darf eine Mannschaft gleichzeitig auf dem Spielfeld haben?"
    },
    ["F"],
    [
      {"5 Feldspieler + 1 Torwart", true, 1},
      {"6 Feldspieler + 1 Torwart", false, 2},
      {"4 Feldspieler + 1 Torwart", false, 3},
      {"5 Feldspieler ohne Torwart", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Wie hoch darf ein Unihockeyschläger maximal gespielt werden?"
    },
    ["F"],
    [
      {"Schulterhöhe des spielenden Spielers", true, 1},
      {"Hüfthöhe", false, 2},
      {"Keine Höhenbeschränkung", false, 3},
      {"Kniehöhe", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Was passiert, wenn der Ball beim **Face-off** direkt ins Tor geht?"
    },
    ["F"],
    [
      {"Kein Tor – Face-off wird wiederholt", true, 1},
      {"Tor zählt", false, 2},
      {"Freistoß für das verteitigende Team", false, 3},
      {"Kein Tor – Freistoß für den Gegner", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Darf ein Feldspieler den Ball mit dem **Fuß** spielen?"
    },
    ["F"],
    [
      {"Nur einmalig – Doppelberührung mit dem Fuß ist verboten", true, 1},
      {"Niemals – nur der Stock ist erlaubt", false, 2},
      {"Ja, uneingeschränkt", false, 3},
      {"Nur innerhalb der eigenen Hälfte", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Wo findet ein **Face-off** nach einem Tor statt?"
    },
    ["F"],
    [
      {"In der Spielfeldmitte", true, 1},
      {"An der Stelle, wo der letzte Schuss abgefeuert wurde", false, 2},
      {"Vor dem Tor, das das Tor erzielte", false, 3},
      {"An der nächsten Face-off-Position", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Was ist beim Unihockey **Handspiel**?"
    },
    ["F"],
    [
      {"Berühren des Balls mit der Hand oder dem Arm – Freistoß für den Gegner", true, 1},
      {"Erlaubt, wenn der Ball von einem Gegner kommt", false, 2},
      {"Nur für Torwarte verboten", false, 3},
      {"Kein Regelverstoß", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Ein Torwart verlässt seinen **Torwartbereich**. Was gilt?"
    },
    ["F"],
    [
      {"Er wird wie ein Feldspieler behandelt und darf keinen Stock benutzen", true, 1},
      {"Er darf weiterhin den Ball mit den Händen spielen", false, 2},
      {"Das Spiel wird unterbrochen", false, 3},
      {"Er erhält sofort eine Zeitstrafe", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ein Spieler hebt den Stock beim Schuss über **Schulterhöhe**. Was entscheidet der Schiedsrichter?"
    },
    ["F"],
    [
      {"Freistoß für den Gegner wegen Hochschlägers", true, 1},
      {"Kein Vergehen – erlaubt beim Schuss", false, 2},
      {"Zeitstrafe für den Spieler", false, 3},
      {"Tor zählt nicht, aber kein Freistoß", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Was ist ein **Penalty** im Unihockey und wann wird er verhängt?"
    },
    ["F"],
    [
      {"Ein Freischuss von der 7-Meter-Linie – bei klarer Torchance mit Regelverstoß", true, 1},
      {"Ein Freistoß vom Mittelkreis", false, 2},
      {"Nur bei Fouls im gegnerischen Torwartbereich", false, 3},
      {"Ein Freischuss von der Strafraumlinie", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Wie lange dauert eine **2-Minuten-Strafe** im Unihockey?"
    },
    ["F"],
    [
      {"2 Minuten reine Spielzeit – endet früher, wenn ein Gegentor fällt", true, 1},
      {"2 Minuten – unabhängig von Gegentoren", false, 2},
      {"Bis zum Ende des Drittels", false, 3},
      {"1 Minute", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "multiple_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "partial_credit",
      body_markdown:
        "Welche der folgenden Vergehen führen typischerweise zu einer **2-Minuten-Zeitstrafe** im Unihockey?"
    },
    ["F"],
    [
      {"Haken (Hooking)", true, 1},
      {"Behindern (Blocking)", true, 2},
      {"Hochschläger mit Gefährdung", true, 3},
      {"Torwart verlässt den Torwartbereich", false, 4},
      {"Ball mit der Hand spielen", false, 5}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Was geschieht, wenn ein Freistoß direkt ins **eigene Tor** gespielt wird?"
    },
    ["F"],
    [
      {"Kein Tor – Ecke für den Gegner", true, 1},
      {"Tor für den Gegner", false, 2},
      {"Freistoß wird wiederholt", false, 3},
      {"Schiedsrichterball in der Spielfeldmitte", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ein Spieler schießt aufs Tor. Der Ball trifft den **Pfosten**, prallt auf den Rücken des Torwarts und geht ins Tor. Zählt das Tor?"
    },
    ["F"],
    [
      {"Ja – der Ball hat die Torlinie vollständig überquert", true, 1},
      {"Nein – ein Eigentor des Torwarts zählt nicht", false, 2},
      {"Nein – der Ball muss vom angreifenden Spieler direkt ins Tor gehen", false, 3},
      {"Nein – der Torwart hat den Ball berührt, Freistoß für die Verteidigung", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ein Spieler steht beim **Penalty** zu früh im Spielfeld (vor dem Mittelpunkt). Was passiert, wenn er das Tor trifft?"
    },
    ["F"],
    [
      {"Penalty wiederholen – unerlaubtes Einlaufen", true, 1},
      {"Tor zählt", false, 2},
      {"Freistoß für die Verteidigung", false, 3},
      {"Zeitstrafe für den einlaufenden Spieler", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "multiple_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "partial_credit",
      body_markdown:
        "Welche Vergehen können im Unihockey zu einer **5-Minuten-Strafe** oder einem **Spielausschluss** führen?"
    },
    ["F"],
    [
      {"Stockschlag gegen den Körper eines Gegners", true, 1},
      {"Absichtliches Spielen des Balls mit dem Gesicht", true, 2},
      {"Wiederholtes unsportliches Verhalten nach Verwarnung", true, 3},
      {"Einfacher Hochschläger ohne Gefährdung", false, 4},
      {"Handspiel im eigenen Bereich", false, 5}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Der Schiedsrichter pfeift **versehentlich** ab, während ein Spieler auf das leere Tor zielt. Wie wird das Spiel fortgesetzt?"
    },
    ["F"],
    [
      {"Face-off an der Stelle, wo der Ball sich befand", true, 1},
      {"Freistoß für die angreifende Mannschaft", false, 2},
      {"Spielfortsetzung ohne Unterbrechung", false, 3},
      {"Penalty für die angreifende Mannschaft", false, 4}
    ]
  )

  # --- J-course questions (Jugendschiedsrichter Unihockey) ---

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Wie lange dauert ein Unihockey-Spiel in der **U13-Jugend** nach IFF-Empfehlung?"
    },
    ["J"],
    [
      {"3 × 15 Minuten (reine Spielzeit)", true, 1},
      {"3 × 20 Minuten", false, 2},
      {"2 × 20 Minuten", false, 3},
      {"2 × 15 Minuten", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Was ist beim Schiedsrichtern in **Jugendspielen** im Unihockey besonders zu beachten?"
    },
    ["J"],
    [
      {"Pädagogisches Verhalten und Erklärungen bei Entscheidungen", true, 1},
      {"Strengere Auslegung der Regeln als bei Erwachsenen", false, 2},
      {"Verzicht auf alle Zeitstrafen", false, 3},
      {"Keine besonderen Unterschiede zu Erwachsenenspielen", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ab welchem **Jahrgang** darf im Unihockey eine offizielle Zeitstrafe verhängt werden?"
    },
    ["J"],
    [
      {"Ab U13", true, 1},
      {"Ab U10", false, 2},
      {"Ab U17", false, 3},
      {"Zeitstrafen gibt es im Jugendbereich nicht", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ein Jugendspieler (U13) beschwert sich lautstark über eine Entscheidung. Wie reagiert der Schiedsrichter idealerweise?"
    },
    ["J"],
    [
      {"Kurze ruhige Erklärung, bei Fortsetzung des Verhaltens: Zeitstrafe", true, 1},
      {"Sofortige Zeitstrafe ohne Erklärung", false, 2},
      {"Spielabbruch", false, 3},
      {"Ignorieren des Verhaltens", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Darf ein Jugendspieler (U16) bei einem Turnier auch in der **U19** eingesetzt werden?"
    },
    ["J"],
    [
      {"Ja, mit entsprechender Genehmigung des Verbands", true, 1},
      {"Nein, das ist grundsätzlich verboten", false, 2},
      {"Nur wenn er mindestens 17 Jahre alt ist", false, 3},
      {"Nur in Freundschaftsspielen", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "In der **U10** – welche vereinfachten Regeln gelten beim Unihockey?"
    },
    ["J"],
    [
      {"Kein Torwart, kleineres Spielfeld, kein offizieller Freistoß", true, 1},
      {"Normale IFF-Regeln wie bei Erwachsenen", false, 2},
      {"Nur Zeitstrafen, keine anderen Sanktionen", false, 3},
      {"Spiel ohne Tor", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Wie viele Auswechslungen sind in einem Unihockey-Jugendspiel erlaubt?"
    },
    ["J"],
    [
      {"Unbegrenzt – fliegender Wechsel während des Spiels", true, 1},
      {"Maximal 3 Wechsel pro Halbzeit", false, 2},
      {"5 Wechsel pro Drittel", false, 3},
      {"Keine Auswechslungen erlaubt", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "multiple_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "partial_credit",
      body_markdown:
        "Welche der folgenden **Vereinfachungen** gelten typischerweise in der **U10** im Unihockey?"
    },
    ["J"],
    [
      {"Kleineres Spielfeld", true, 1},
      {"Kein Torwart", true, 2},
      {"Keine Zeitstrafen", true, 3},
      {"Kein Penalty", true, 4},
      {"Kein Face-off", false, 5}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ein U13-Jugendspieler erhält seine zweite **Zeitstrafe** im selben Spiel. Was folgt?"
    },
    ["J"],
    [
      {"Spielausschluss für den Rest des Spiels", true, 1},
      {"Nur eine weitere 2-Minuten-Strafe", false, 2},
      {"Verwarnung durch den Schiedsrichter", false, 3},
      {"Nichts – zwei Zeitstrafen sind normal", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "In einem **U16**-Spiel fällt der einzige Schiedsrichter aus. Was kann das Ergebnis sein?"
    },
    ["J"],
    [
      {"Das Spiel wird abgebrochen, Ergebnis wird durch zuständige Instanz festgelegt", true, 1},
      {"Ein Spieler übernimmt das Schiedsrichteramt", false, 2},
      {"Das Spiel zählt als 0:0", false, 3},
      {"Das Spiel wird zu einem späteren Zeitpunkt nachgeholt", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "multiple_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "partial_credit",
      body_markdown: "Welche **besonderen Pflichten** hat ein Jugendschiedsrichter im Unihockey?"
    },
    ["J"],
    [
      {"Besonderes Augenmerk auf faire und respektvolle Spielweise", true, 1},
      {"Erklärung von Entscheidungen in altersgerechter Sprache", true, 2},
      {"Abbruch bei massiven Unsportlichkeiten durch Erwachsene am Spielfeldrand", true, 3},
      {"Keine Zeitstrafen aussprechen", false, 4},
      {"Alle Regeln vereinfachen", false, 5}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ein **U19**-Spieler wird kurz vor seinem 19. Geburtstag eingesetzt. Darf er nach dem Geburtstag noch in der U19 spielen?"
    },
    ["J"],
    [
      {"Ja, bis zum Ende der laufenden Saison", true, 1},
      {"Nein, er muss sofort zu den Senioren wechseln", false, 2},
      {"Nur mit besonderer Ausnahmegenehmigung", false, 3},
      {"Ja, bis zum nächsten offiziellen Spieltag", false, 4}
    ]
  )

  # --- G-course questions (Turnierschiedsrichter Unihockey) ---

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Wie groß ist ein **reguläres Unihockey-Spielfeld** nach IFF-Regeln?"
    },
    ["G"],
    [
      {"40 × 20 Meter", true, 1},
      {"44 × 22 Meter", false, 2},
      {"30 × 15 Meter", false, 3},
      {"50 × 25 Meter", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Wie hoch sind die **Banden** auf einem regulären Unihockey-Spielfeld?"
    },
    ["G"],
    [
      {"50 cm", true, 1},
      {"30 cm", false, 2},
      {"75 cm", false, 3},
      {"1 Meter", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Was passiert beim Turnier, wenn der Ball die **Bande** verlässt?"
    },
    ["G"],
    [
      {"Freistoß für die nicht zuletzt berührende Mannschaft an der Stelle, wo der Ball die Bande verließ",
       true, 1},
      {"Einwurf wie beim Hallenfußball", false, 2},
      {"Face-off an der nächsten Face-off-Position", false, 3},
      {"Das Spiel läuft weiter", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Wie viele **Schiedsrichter** leiten ein offizielles Unihockey-Spiel nach IFF-Regeln?"
    },
    ["G"],
    [
      {"2 gleichberechtigte Schiedsrichter", true, 1},
      {"1 Hauptschiedsrichter + 2 Linienrichter", false, 2},
      {"1 Schiedsrichter", false, 3},
      {"3 Schiedsrichter", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Wie lange dauert eine **Pause** zwischen den Dritteln beim Unihockey-Turnier?"
    },
    ["G"],
    [
      {"10 Minuten", true, 1},
      {"5 Minuten", false, 2},
      {"15 Minuten", false, 3},
      {"20 Minuten", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Was geschieht beim Turnier, wenn ein Spieler nach einer **Zeitstrafe** zu früh das Strafbankbereich verlässt?"
    },
    ["G"],
    [
      {"Neue Zeitstrafe für die restliche Zeit plus 2 Minuten", true, 1},
      {"Verwarnung durch den Schiedsrichter", false, 2},
      {"Spielausschluss", false, 3},
      {"Freistoß für den Gegner", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Bei einem Unihockey-Turnier erhält Team A insgesamt **6 Zeitstrafen** in einem Drittel. Was kann der Schiedsrichter anordnen?"
    },
    ["G"],
    [
      {"Spielabbruch und Spielverlust, wenn das Verhalten anhält", true, 1},
      {"Nichts Besonderes – Strafen werden normal abgezählt", false, 2},
      {"Automatischen Penalty für den Gegner", false, 3},
      {"Torwechsel erzwingen", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "multiple_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "partial_credit",
      body_markdown:
        "Welche **Unterschiede** gelten beim Unihockey-Turnier gegenüber einem normalen Spielbetrieb?"
    },
    ["G"],
    [
      {"Angepasste Spielzeiten je nach Turnierformat", true, 1},
      {"Möglicherweise keine Pause zwischen den Dritteln", true, 2},
      {"Turnierspezifische Regeln für Verlängerung und Penaltyschießen", true, 3},
      {"Keine Zeitstrafen bei Turnieren", false, 4},
      {"Kleinere Banden erlaubt", false, 5}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "medium",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Was gilt beim **Penaltyschießen** im Unihockey nach Unentschieden?"
    },
    ["G"],
    [
      {"Jede Mannschaft schießt abwechselnd 5 Penalties; bei Gleichstand weiter je 1", true, 1},
      {"Sofortiger Golden Goal in der Verlängerung", false, 2},
      {"Das Spiel endet unentschieden", false, 3},
      {"Ein Face-off in der Spielfeldmitte entscheidet", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ein Spieler beim Turnier schlägt den Ball absichtlich **über die Bande**. Was entscheidet der Schiedsrichter?"
    },
    ["G"],
    [
      {"Zeitstrafe für unsportliches Verhalten + Freistoß für den Gegner", true, 1},
      {"Nur Freistoß, keine Strafe", false, 2},
      {"Spielausschluss wegen Spielunterbrechung", false, 3},
      {"Kein Foul – Ball ist out", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Ein Spieler beim Turnier erhält eine **5-Minuten-Strafe**. Wie lange muss sein Team in Unterzahl spielen?"
    },
    ["G"],
    [
      {"Die volle Spielzeit von 5 Minuten – endet nicht bei einem Gegentor", true, 1},
      {"Bis ein Gegentor fällt", false, 2},
      {"Bis zum Ende des Drittels", false, 3},
      {"2 Minuten wie bei einer normalen Zeitstrafe", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "multiple_choice",
      difficulty: "high",
      status: "active",
      scoring_mode: "partial_credit",
      body_markdown:
        "Welche **Anforderungen** gelten für einen Schiedsrichter beim Unihockey-Turnier besonders?"
    },
    ["G"],
    [
      {"Schnelle Entscheidungsfindung auf dem kleinen Spielfeld", true, 1},
      {"Kenntnis des jeweiligen Turnierregelwerks", true, 2},
      {"Kommunikation mit dem Turnierleiter bei Regelfragen", true, 3},
      {"Zwingend zwei Schiedsrichterassistenten", false, 4}
    ]
  )

  # shared F+J+G questions
  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown:
        "Welche Farbe hat das **Trikot** der Schiedsrichter im Unihockey üblicherweise?"
    },
    ["F", "J", "G"],
    [
      {"Die Kleidung muss sich von der der Spieler beider Mannschaften unterscheiden", true, 1},
      {"Immer schwarz", false, 2},
      {"Immer weiß", false, 3},
      {"Keine Vorschriften", false, 4}
    ]
  )

  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "active",
      scoring_mode: "exact_match",
      body_markdown: "Welche Maßnahme folgt auf eine **5-Minuten-Strafe**?"
    },
    ["F", "J", "G"],
    [
      {"Spieler verbüßt 5 Minuten, ein Ersatzspieler darf nach 2 Minuten einrücken", true, 1},
      {"Spielausschluss des Spielers für das gesamte Spiel", false, 2},
      {"2 Minuten + automatische Spielsperre für das nächste Spiel", false, 3},
      {"Sofortiger Spielausschluss ohne Ersatz", false, 4}
    ]
  )

  # draft questions (for testing draft state)
  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "draft",
      scoring_mode: "exact_match",
      body_markdown: "**Entwurf:** Diese Frage ist noch nicht veröffentlicht."
    },
    ["F"],
    [
      {"Antwort A", true, 1},
      {"Antwort B", false, 2}
    ]
  )

  # archived question (for testing archived/deactivated state)
  Seeds.Questions.create!(
    %{
      type: "single_choice",
      difficulty: "low",
      status: "archived",
      scoring_mode: "exact_match",
      body_markdown:
        "**Archiviert:** Diese Frage wurde deaktiviert und wird nicht mehr verwendet."
    },
    ["F"],
    [
      {"Antwort A", true, 1},
      {"Antwort B", false, 2}
    ]
  )

  IO.puts("  Fragen erstellt.")
else
  IO.puts("  Fragen existieren bereits – übersprungen.")
end

# ---------------------------------------------------------------------------
# 7. Courses
# ---------------------------------------------------------------------------

IO.puts("\n--- Kurse ---")

if Repo.aggregate(Whistle.Courses.Course, :count) == 0 do
  courses_data = [
    # Saison 2025 – abgeschlossen
    {"Feldschiedsrichter Grundlehrgang Nord", "F", ~D[2025-03-15], season_2025.id, hsv.id, 20, 3},
    {"Jugendschiedsrichter Kurs Hamburg", "J", ~D[2025-04-10], season_2025.id, hfv.id, 15, 2},
    {"Hallenschiedsrichter Turnierkurs", "G", ~D[2025-02-20], season_2025.id, shfv.id, 12, 2},
    # Saison 2026 – aktuell
    {"Feldschiedsrichter Grundlehrgang 2026", "F", ~D[2026-05-10], season_2026.id, hsv.id, 20, 3},
    {"Feldschiedsrichter Aufbaukurs Nord", "F", ~D[2026-06-14], season_2026.id, nfv.id, 18, 3},
    {"Jugendschiedsrichter Kurs 2026", "J", ~D[2026-05-24], season_2026.id, hfv.id, 15, 2},
    {"Jugendschiedsrichter Fortbildung", "J", ~D[2026-07-05], season_2026.id, shfv.id, 12, 2},
    {"Hallenschiedsrichter Turnierkurs 2026", "G", ~D[2026-04-12], season_2026.id, bfv.id, 10, 2}
  ]

  courses =
    Enum.map(courses_data, fn {name, type, date, season_id, organizer_id, max_p, max_club} ->
      {:ok, c} =
        Courses.create_course(%{
          name: name,
          type: type,
          date: date,
          season_id: season_id,
          organizer_id: organizer_id,
          max_participants: max_p,
          max_per_club: max_club,
          max_organizer_participants: max_club
        })

      # Release all courses so registration is possible
      {:ok, c} = Courses.release_course(c)
      IO.puts("  Erstellt: #{name}")
      c
    end)

  # ---------------------------------------------------------------------------
  # 8. Registrations
  # ---------------------------------------------------------------------------

  IO.puts("\n--- Anmeldungen ---")

  [_f2025, _j2025, _g2025, f2026, f2026b, j2026, _j2026b, g2026] = courses

  registrations = [
    # F 2026 – full group
    {f2026, [mueller, schmidt, weber, fischer, wagner, becker, hoffmann, schulz, braun, klein]},
    # F 2026b – partial group
    {f2026b, [wolf, richter, mueller, weber]},
    # J 2026
    {j2026, [fischer, wagner, becker, hoffmann, schulz]},
    # G 2026
    {g2026, [braun, klein, wolf, richter]}
  ]

  Enum.each(registrations, fn {course, participants} ->
    Enum.each(participants, fn user ->
      {:ok, _} = Registrations.enroll_one(user, course, admin.id)
    end)

    IO.puts("  #{length(participants)} Anmeldungen für: #{course.name}")
  end)

  # ---------------------------------------------------------------------------
  # 9. Exams
  # ---------------------------------------------------------------------------

  IO.puts("\n--- Prüfungen ---")

  # Exam 1: waiting room (ready to start)
  {:ok, exam_waiting} =
    Exams.create_exam(
      f2026,
      Enum.map([mueller, schmidt, weber, fischer, wagner], & &1.id),
      admin.id,
      title: "F-Prüfung Mai 2026 (Gruppe A)"
    )

  IO.puts("  Erstellt: #{exam_waiting.title} [#{exam_waiting.state}]")

  # Exam 2: currently running
  {:ok, exam_running} =
    Exams.create_exam(
      f2026,
      Enum.map([becker, hoffmann, schulz, braun, klein], & &1.id),
      admin.id,
      title: "F-Prüfung Mai 2026 (Gruppe B)"
    )

  {:ok, exam_running} = Exams.update_exam_state(exam_running, "running")
  Exams.broadcast(exam_running.id, {:exam_state_changed, exam_running})
  IO.puts("  Erstellt: #{exam_running.title} [#{exam_running.state}]")

  # Exam 3: finished and scored
  {:ok, exam_finished} =
    Exams.create_exam(f2026b, Enum.map([wolf, richter, mueller, weber], & &1.id), admin.id,
      title: "F-Prüfung April 2026"
    )

  {:ok, exam_finished} = Exams.update_exam_state(exam_finished, "running")
  {:ok, exam_finished} = Exams.update_exam_state(exam_finished, "finished")
  Exams.score_exam(exam_finished)
  IO.puts("  Erstellt: #{exam_finished.title} [#{exam_finished.state}]")

  # Exam 4: J-course, waiting room
  {:ok, exam_j} =
    Exams.create_exam(
      j2026,
      Enum.map([fischer, wagner, becker, hoffmann, schulz], & &1.id),
      admin.id,
      title: "J-Prüfung Mai 2026"
    )

  IO.puts("  Erstellt: #{exam_j.title} [#{exam_j.state}]")

  # Exam 5: canceled
  {:ok, exam_canceled} =
    Exams.create_exam(g2026, Enum.map([braun, klein], & &1.id), admin.id,
      title: "G-Prüfung April 2026"
    )

  {:ok, exam_canceled} = Exams.update_exam_state(exam_canceled, "canceled")
  IO.puts("  Erstellt: #{exam_canceled.title} [#{exam_canceled.state}]")
else
  IO.puts("  Kurse existieren bereits – Kurse, Anmeldungen und Prüfungen übersprungen.")
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

IO.puts("""

╔══════════════════════════════════════════════════════╗
║              Seed-Daten erstellt ✓                   ║
╠══════════════════════════════════════════════════════╣
║  Login:  admin@nordref.de   Passwort: Testpasswort123!  ║
║  Benutzer-Passwort (alle):  Testpasswort123!            ║
╠══════════════════════════════════════════════════════╣
║  Prüfungen:                                          ║
║  • F Mai 2026 (Gruppe A)  → Warteraum               ║
║  • F Mai 2026 (Gruppe B)  → Läuft                   ║
║  • F April 2026           → Beendet + bewertet       ║
║  • J Mai 2026             → Warteraum               ║
║  • G April 2026           → Abgebrochen             ║
╚══════════════════════════════════════════════════════╝
""")
