# UX walkthrough, 2026-11-07

An end-to-end walk of the app on `main` at `20f820d` (PR #1 merged), on the iOS 27
simulator (iPhone 17, dark mode, with light-mode spot checks). Every screen was
photographed along the way.

The walk covered three things:

- **A fresh install:** the five intro pages, the notification prompt, the site
  chooser and day 1.
- **Every tab and its sub-screens:** the dashboard tiles and their details, Nest,
  Jobs, World, Garden, the capture flow, the species picker, flower detail, Field
  Guide, Record (Lineage, Almanac, Collection, Milestones, History) and Settings.
- **A day-709 colony** reopened after a long absence, to see the "While You Were
  Away" report and the winter dashboard.

The screenshots are in `build/ux-walkthrough-2026-11-07b/`, which git ignores. The
`v` prefix marks the re-check after the fixes.

An earlier pass the same morning ran on the pre-merge build. Its findings were
re-checked here, and only those that still held are listed.

| Tag | Meaning |
|---|---|
| **FIXED** | Changed, rebuilt and seen working on the simulator |
| **OPEN** | Still as found, for a decision or a later pass |

## Already fixed by the merge

The earlier pass flagged these, and the merged code had already dealt with them:

- The disabled "Take" and "Feed" buttons were a blank black pill.
- The Jobs list re-sorted after a tap.
- A day-1 colony was offered 44 units of honey to take.
- The catch-up report put its summary below about 40 log lines and repeated
  identical events.
- **Capture failed in the simulator.** Vision threw "Failed to create espresso
  context" and the photograph was lost. The plant check now steps aside when
  Vision cannot run, and the identification ladder carries on.

The disabled-button and Jobs fixes came from this session's first pass and were
swept into the merge. Capture was seen working end to end today.

## Fixed in this pass

1. **FIXED. Jobs: the blank middle of a row did nothing.**
   - `contentShape` sat on the `Button` from outside, where it never reached the
     gesture.
   - It now sits on the label, and tapping between the name and the count pins
     the job (`v07`).
2. **FIXED. Picking from the library could raise two permission prompts in a row.**
   - The first prompt asked for read access, needed for the original's date.
   - On a no, the app saved a copy back into the library. That raised a second
     prompt, for adding photos, and on a yes left a duplicate in the camera roll.
   - An unreadable pick is now kept in the app's own container, the way a
     received flower is. There is one prompt and no duplicate (`v18`, `v19`).
3. **FIXED. The status said "Steady" beside "Clustered, and short of stores".**
   - Stores counted towards the status only in autumn.
   - Winter now uses the same test as the headline, `Hive.isShortForWinter`, so
     the status reads "Struggling" (`v01`).
4. **FIXED. Cave was described as "safe" and "cold".**
   - The engine gives it the joint-highest insulation (0.90) and below-tree
     defensibility (0.60), and the bars drawn beside the copy say so.
   - The copy now matches the bars, and so does the glossary entry (`v15`).
5. **FIXED. "The colony cleared american foulbrood."**
   - The name was lowercased wholesale.
   - `Pathogen.nameInSentence` now gives "American foulbrood" in the report and
     in the almanac (`v11`).
6. **FIXED. The report's health card listed a cleared disease only as "appeared".**
   - `CatchUpReport` now records cleared infections.
   - The card says "American Foulbrood appeared, and was cleared" (`v10`).
7. **FIXED. A trace infection showed "<1%" on its tile and "0%" in its detail.**
   The detail now says "a trace" (`v02`).
8. **FIXED. The report's "Forage and weather" row wrapped onto two centred lines.**
   Each tally now sits under its heading (`v09`).
9. **FIXED. Record was five chips in a ragged grid, with a paragraph explaining
   them.**
   - It is now a list, with one line under each entry saying what it is.
   - The paragraph is down to the one fact that covers all five (`v03`).
10. **FIXED. The Forage detail listed "Pussy Willow" three times, two lines
    identical.**
    - Wild stands of one plant now fold into a single line: "Pussy Willow ×3,
      800–1400 m" (`v16`).
    - The player's own flowers stay one per line.
11. **FIXED. The population trend "→" sat beside the chevron and read as a second
    way in.**
    - The arrow now sits beside the number.
    - A steady trend draws no arrow (`v01`).
12. **FIXED. The keystone star on the dashboard and Collection bloom card had no
    legend.** A caption explains it when a star is shown.
13. **FIXED. The hemisphere picker read "Northern | Southern" with no noun.**
    - Onboarding names both hemispheres in full, and its copy now says what is
      being chosen (`v13`).
    - Collection labels the picker.
14. **FIXED. The notifications intro read like design notes.**
    - The second paragraph is now said to the player.
    - It names the three notification switches that "any of the three" left
      undefined (`v14`).
15. **FIXED. Collection's season buttons broke "Sum-mer" and "Au-tumn" mid-word.**
    They now stay on one line and shrink to fit (`v17`).
16. **FIXED. The World map was a bright cream block in dark mode.**
    - The paper is now dim in dark mode (`v12`).
    - Rumoured cells get a softer outline, which full-strength wax had turned
      into a loud grid.
    - Light mode is unchanged (`v22`).
17. **FIXED. The pinned comb left the job list a strip with its first rows cut
    off.**
    - The comb is now capped at 290 pt wide, about 250 pt tall.
    - That gives back roughly one more row (`v06`).
18. **FIXED. The Nest card said "66 / 700 cells" over "44 free".** It now reads "66
    of 700 cells built" and "Comb in Use … 44 empty".
19. **FIXED. A result gave "Confidence 100%", and "80%" under a name the player
    had just chosen.**
    - The model's confidence is now in words: "Very sure", "Fairly sure",
      "Unsure" or "A guess". The percentage is still read out to VoiceOver.
    - A name the player chose says "Named by you" (`v19`, `v21`).
20. **FIXED. Names from the full plant list were lower case.** "liquorice plant"
    sat beside "Pussy Willow"; first letters are now raised (`v20`).
21. **FIXED. Lineage said the founding queen "Emerged year 1, day 1".**
    - The Queen tile gave her age as ten days.
    - She now "Emerged before the swarm settled", and her mating carries no day
      (`v04`).
22. **FIXED. The Honey detail explained the surplus twice in a row.** The second
    explanation now only covers how the surplus moves through the year.
23. **FIXED. History said "Come back tomorrow".** It now says a hive day is about
    two hours of yours.
24. **FIXED. An uncatalogued species was called "A family the catalogue has no
    notes on".** The note now says the catalogue has no notes on *this family*.

## Open

25. **OPEN. One garden-cell tap planted the flower in a different cell.**
    - Seen once: tapped west, planted east. A repeat went where it was tapped.
    - Suspect: `ContentView.show()` re-presents the root sheet when it has not
      appeared within 1.5 s. The dismissal runs `sheetClosed`, which clears
      `plantingCell`, so a slow first presentation would lose the cell.
    - Not reproduced, so nothing was changed.
26. **OPEN. The species search shows an empty sheet for about 3 s before results
    appear.** It needs a "Searching…" state.
27. **OPEN. Identification takes about 30 s on the simulator.** BioCLIP runs on the
    CPU there. It needs measuring on a phone; if it is still slow, the "Looking at
    it…" screen should say it can take a moment.
28. **OPEN. The read-access prompt arrives mid-identification, after a photo was
    already picked.** It is the moment the access is needed. Asking before the
    picker would at least be expected.
29. **OPEN. The Queen tile says "Laying" in winter with no brood.** Either the state
    name or the winter wording should change.
30. **OPEN. Field Guide says "Photographed 0 of 30" when the garden holds two
    flowers outside the catalogue.**
31. **OPEN. Collection's "Not yet found" rows carry grey counts with no label.**
32. **OPEN. Flower detail shows "100% forage left" in a tile and again in "Right
    now".** The share and Done buttons also float over the scrolled title.
33. **OPEN. Settings repeats the garden counts from elsewhere and has long
    footers.** One footer covers three different settings.
34. **OPEN. The Stores detail does not show the "% of what winter needs" that its
    tile leads with.** On day 1 its trace has no history yet, so "60 honey" sits
    beside "0 to spare" with nothing explaining the gap.
35. **OPEN. The day-1 bloom card has no button to photograph a flower.** The
    camera is in the toolbar.

## Not localised yet

The new and changed strings are not in `Localizable.xcstrings`, because
`xcodebuild` does not sync the catalogue. Opening the project in Xcode and
building there will add them.
