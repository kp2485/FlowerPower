# The overview, 2026-11-08

The Colony tab redrawn as one screen, on Kyle's direction: "a more simplified
and categorized UI to see an overview on one screen with the ability to drill
down into the details", and then "2 columns … fit the entire first screen with
no scrolling required unless the user needs larger text sizes for
accessibility". Checked on the iOS 27 simulator (iPhone 17), dark and light,
at the default text size and at the accessibility extra-large size. The
screenshots are in `build/overview-2026-11-08/`, which git ignores, with the
day-14 save and the aged save used for them beside them.

## What changed

- **Four cards, two abreast** replace the grid of eight tiles: The Bees, The
  Larder, Inside, Outside. Each is a short list of one-line readings — symbol,
  what it is, one number, a colour for how worried to be — and a heading in
  small capitals with a dot in the worst line's colour when anything under it
  is a caution or an alarm. Which card a reading sits in is
  `DashboardSummary.Section` in the package, with tests.
- **Every line is a way in.** A reading opens the full-size page it stands
  for, unchanged, in `ColonyDetailViews.swift`. A *place* — Jobs, Comb,
  Country, Garden — opens the tab that draws it, through a new `openTab`
  environment action `ContentView` sets. So the first screen stands in for
  the tab bar.
- **The record moved into the header** as "Year 1 · Day 14 ›". A heading over
  one line was a heading over nothing, and the day is where the record
  belongs.
- **The bloom prompt is a line, not a card.** "Look For — 12 — Viper's Bugloss
  first" sits in Outside and opens the Forage page, which now carries the full
  card with its camera button at the top. The card was the one thing on the
  old dashboard that never fitted above the fold. The Forage page lost its own
  camera button, which had become the same button twice.
- **The title is inline.** The status card under it is the real header, and
  the large title cost the last card its place on the screen.
- **At the accessibility sizes** the two columns become one, the number drops
  under its title, and the screen scrolls.

## The rule the layout is held to

Everything above the tab bar at the default text size, with room for the
decision rows and the attention row when they appear. Measured on the iPhone
17: with two open decisions the four cards end about 100 pt above the tab bar.

## Not localised yet

The new strings are not in `Localizable.xcstrings`; an Xcode.app build adds
them.

## The same day, later: three tiers, and no white space

Kyle asked whether the overview could size itself from the watch to the iPad
and still honour every text size, and then that white space be minimised and
the elements aligned. Built as three tiers, with one disagreement recorded
below.

- **Full and compact on the phone and the iPad.** How many cards sit abreast
  comes from the measured page width and a text-scaled minimum card width
  (`DashboardSummary.columns(fitting:minimumCardWidth:)`): two on an
  iPhone 17, four on an 11-inch iPad, one from two text steps up on a
  phone. At the accessibility sizes the lines drop their captions and keep
  their titles (`Density.compact`).
- **Symbol on the watch.** `WatchSummary.readings` now carries every reading
  as strings with its severity, decoded leniently so an older phone or
  watch still works. The watch's numbers page is a two-column grid of glyph
  and number in the colour of how worried to be, each tappable to the words;
  it falls back to the old numbers page when a phone sends no readings. To
  build the readings the engine needed `DashboardSummary`, so it moved from
  the game layer into the engine; the "look for" line, which needs the
  calendar and the hemisphere, stayed behind in
  `DashboardSummary+LookFor.swift`.
- **The disagreement.** Kyle suggested defaulting to symbols at the larger
  text sizes. The phone never does: someone who turns the text up is asking
  to read, and Apple's guidance is to stack and scroll rather than remove
  words. Symbols are for the surfaces that are physically small.
- **Three lines a card.** The cards were 3, 2, 2 and 4 lines, so their
  edges never met. Two readings were added — Entrance (open or sealed, and
  what the guards are doing) and Intake (what came in today) — and the Garden
  line went, Forage and Look For being the flowers already. Health is the one
  thing allowed to make a fourth line, when there is something to say.
- **The cards fill the screen.** When the page fits, it is not a scroll
  view: `ViewThatFits` takes the filling layout, whose lines grow together to
  a cap so the grid ends where the screen does. A wide screen gets a second
  row under its four cards — the bloom prompt and the population and stores
  charts, stretched to one height.

Screenshots `20-` to `36-` in `build/overview-2026-11-08/`: the phone in
spring with three decisions open and in winter with one; the iPad at four
columns with its second row; the watch's readings page. The watch page was
photographed by putting it first in the page order for one build and
reverting; the simulator's own navigation needs an access grant the panel
was still waiting on.
