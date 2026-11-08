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
