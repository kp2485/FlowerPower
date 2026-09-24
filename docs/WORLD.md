# The world around the hive

A design for a procedurally generated sandbox the colony lives in: as wide as
bees fly, drawn chunk by chunk as they discover it, with biomes to colonise
and a garden the player builds beside the nest. Written 2026-09-15, the day
real-world location came out of the app, to answer the question that removal
left in PLAN.md — *whether a patch's distance should ever vary again, and
where it would come from if not from where the player was standing.* This is
where.

**Phase 1, "the ground", was built the same day** — see section 11, and PLAN.md
under "the ground" for the record of it. **Phase 2, "the country", was built on
2026-09-16**: wild forage, the fog, exploration, scouts as a decision, and the
biome multipliers. PLAN.md's "the country" is the record, section 11 below lists
what was done differently and why, and every one of section 10's measurements
has now been taken. Everything from Phase 3 on is still a design. Every number
that is not marked as the engine's own, or as measured, is a starting point to
be measured in the manner PLAN.md section 4 describes.

---

## 1. What the bees know

A honey bee's world is a circle about five miles across with the nest at the
centre. She has no map of it. She knows what the dancers on the comb have told
her — a direction, a distance, how hard they danced — and what she has found
herself. Beyond the last patch anyone has danced for, there is nothing; not
darkness, just nothing, until a scout comes back from it.

That is the world this game draws. The player does not get a map of the
countryside and choose where to put a hive on it. They get the hive, and the
countryside appears around it in the order the bees find it, and it stops
where the bees stop. Eight kilometres out — `FlowerPatch.maximumForagingRange`,
the engine's edge — is the edge of the world, until a swarm leaves and takes
its own circle with it.

Two things follow from that, and the whole design hangs on them.

**Distance is the game's oldest lever and it has never been pulled.** The
engine prices every trip: a patch's yield falls as `1 / (1 + metres / 1600)`
— 1.0 at the entrance, 0.67 at the nominal 800 m every flower has ever sat at,
0.35 at three kilometres, 0.17 at eight — and the honey a forager burns
getting there rises as `1 + metres / 2000`. The waggle dance weights patches by
`richness × distance efficiency × rarity × keystone × vigour` to the power 1.6,
so a colony converges on the best nearby thing rather than spreading. All of
this is in the balance that produced 89% first-year and 66% second-year
survival. None of it has ever varied, because the only proposed source of
distance was GPS and the hive never received a coordinate. A world in which
the garden is at 200 m and the heather is at five kilometres is a world in
which the numbers already in the engine start to mean something.

*Two corrections, 2026-09-15.* The 89%/66% was measured at 400 m, not at the
nominal 800 m the app used — `beesim --distance` defaults to 400 — so the app's
own flowers were at 0.67 and the trials' were at 0.80, and the recorded baseline
was never the app's. And the lever has been pulled: Phase 1 plants a photograph
in a cell of the garden, and the cell's distance from the nest is the patch's
`distanceMetres`. Section 10 item 1 has the measurement.

*A third correction, 2026-09-16, and it is about the dance rather than about the
measurement.* The paragraph above says the dance weights patches by `richness ×
distance efficiency × …`, and that is exactly what was wrong: the recruitment
weight fell off with distance at the same gentle `1 / (1 + m / 1600)` slope as
the yield, so a full stand five kilometres out outranked a half-worked one at
the door. Seeley's finding is that the dance threshold rises with distance far
faster than the profit falls — a distant source has to be *much* better before
anybody dances for it at all. Nothing before Phase 2 could see this, because
every patch in every trial stood at one distance. `danceDistanceExponent` raises
the distance term in the recruitment weight only, leaving the harvest on the
plain efficiency, which is flight physics. Swept over 200 colonies, garden on at
two years / `--policy scout` / wild forage alone in the first year: 1.0 → 56% /
2% / 38%; 1.5 → 60 / 25 / 48; 2.0 → 64 / 55 / 52; 3.0 → 69 / 66 / 64. It ships
at **3.0**. With a colony whose patches all stand at one distance the factor
cancels when the shares are normalised, so every world-off number ever recorded
is untouched by it — measured, not assumed: the 400 m baseline diffs clean at
exponent 1 and at exponent 3.

**More forage does not mean more survival.** This is the finding that sits
under the whole balance (`SimulationConfig.sharedPatchYield`'s comment,
PLAN.md's gentle preset): a colony fed entirely on shared flowers survives as
well as one fed on its own, richer forage alone dropped survival from 70% to
40%, and the gentle preset is *worse* at two years than the standard one,
because well-fed colonies swarm more. Survival is bounded by comb space and
colony dynamics, not by what is on offer. So a world full of wild flowers does
not make the game easy. It makes colonies swarm — and swarming is how a colony
reproduces, and reproducing is how the map grows. The world's abundance and
the world's expansion are the same mechanic seen from two sides.

## 2. Where it comes from

The 2023 layer, retired today, had this in it. Its design document proposed a
`MapView` where "the map starts undiscovered and a fog of war exists after
bees depart an area", a "sandbox which extends beyond what is displayed on the
screen", and — in the last amendment ever made to it — a `WorldMapView`: "a
grid of varying terrain types and respective maps which the player progresses
through over time", with "a difficulty level for each grid square", after
which "users can create a new queen and migrate out to a new area … and go
back to previously colonised squares." Its `BiomeModel.swift` was a schema
that was never instantiated, but it had one genuinely generative idea: each
placed feature — a pond, an outcrop, a barn, a house — carried a
`cavityProbability`, so the same pass that dressed the terrain decided where a
swarm could live. That idea is kept below. The tower-defence half of that
document is not, for the reason PROPOSALS.md gives: it is the minigame that
stalled the project, and this is an idle game.

What the 2026 engine already has that the 2023 design only named: ten nest
sites with measured room, warmth, defensibility and ground exposure; 21
predators with seasons and attack styles; a catalogue of 30 species, each with
measured floral traits and a field note saying where it grows; seasons,
weather and a deterministic clock; and a swarm that is preserved when it
leaves so that it can be followed. The world is mostly a matter of giving
those things somewhere to be.

## 3. The shape of the ground

**Hexagons, 200 metres across.** A hex has six neighbours at equal distance,
which makes straight-line distance honest in every direction — a square grid
lies about diagonals — and it is the shape of the comb, which is not nothing.
Two hundred metres is a bee's minute in the air, about the width of a field,
and small enough that a garden of six cells around the nest is all within
400 m. The distance from the hive to any cell is the hex distance times 200 m,
and that number is what goes into `FlowerPatch.distanceMetres`. The eight-
kilometre range is a radius of forty cells.

**Chunks of 37 cells** — a hexagon three cells deep around a centre — about
1.4 km across, roughly a parish. A chunk is the unit that is generated,
discovered and named. The range circle holds about a hundred of them; a
player will see a dozen in a colony's life and every one will have been
reached by a bee. The word "chunk" is for the code; the player never sees
it. They see a stretch of country with a name the generator gives it — the
chunk's biome and its notable feature: *Mill Meadow*, *Heather Bank*, *the
Churchyard at Coldharbour*.

**Generated, never stored.** A chunk is a pure function of the world seed and
its coordinates. The save records only what has *happened*: which chunks have
been discovered, what the player has planted, which sites have been founded,
which wild colonies stand. Everything else is regenerated on demand, which is
why the save does not grow with the map and why an old save opens with the
world derived around it (section 9). Determinism is the rule the whole engine
already keeps: the generator draws from its own `SeededRandom` seeded
arithmetically from `(worldSeed, q, r)`, never from the colony's RNG, never
through `Hasher`, and walks cells in a fixed order — so a chunk is the same on
the phone, on the watch, in `beesim` on Windows, and in a save opened next
year.

## 4. The biomes

There are seven, and they come from the field guide rather than the other way
round: the thirty species already say where they grow, so the biome table is
the catalogue sorted by habitat. Each biome has a bloom calendar that falls
out of its species' seasons, a set of nest sites its features can roll, and a
subset of the predator roster. A chunk is one biome, with the edges of its
neighbours bleeding a cell or two across.

| Biome | What grows there (from the field notes) | Its year | Sites its features offer | Who hunts there |
|---|---|---|---|---|
| **Meadow and pasture** | white clover ("in every mown lawn"), dandelion, thistle ("in pasture and on roadsides"), meadowsweet on the damp side | spring through autumn, never a flow, never empty | animal burrow; fallen tree at the margin | badger, toad, ant, crab spider |
| **Hedgerow and field margin** | hawthorn, bramble ("in hedges and waste ground"), borage and phacelia ("sown deliberately in field margins"), poppy, ivy on the old trees ★ | a spring flow of hawthorn, bramble all summer, ivy in October | living tree cavity in a hedgerow oak; fallen tree | wasp, hornet, mouse, shrike |
| **Old woodland** | bluebell ("carpeting old woodland", at the limit of a bee's tongue), foxglove at the edge (out of reach), hawthorn on the rides, ivy ★ | thin — a spring carpet the bees can barely use, then ivy | living tree cavity, the best there is; fallen tree; burrow | badger, woodpecker, honey buzzard, mouse, wax moth |
| **Riverbank and wet ground** | willow ★ ("damp ground, riverbanks and scrub"), Himalayan balsam ("in stands along riverbanks"), meadowsweet ("damp meadows and ditch sides") | the first flow of the year, and the last big one | fallen tree; under a branch; a damp burrow | toad, dragonfly, mouse |
| **Farmland** | oilseed rape ("whole fields of four-petalled yellow crosses"), sunflower, phacelia, poppy on the disturbed ground | one enormous fortnight of yellow, then very little | a barn or shed roof; a nestbox if the farmer keeps bees | the farmer (the `human` catastrophe), robber bees from an apiary, ant |
| **Village, gardens and churchyard** | crocus ★ ("lawns, park verges and churchyards"), lavender, echinacea ("a border plant"), Michaelmas daisy, ice plant, rosemary ★, winter heather ★ ("rockeries and gardens"), mahonia ★, lime ("high in a big street tree"), apple and cherry | the only biome with something out all year; the only winter forage in the game | inside walls, "the best site in the game, if you do not mind the neighbours"; a chimney or shed; nestbox | wasp, raccoon, opossum, skunk, human |
| **Heath, moor and down** | heather ★ ("colouring whole moors from August. Acid, peaty ground"), goldenrod ("dry banks and railway ground"), viper's bugloss ★ ("chalk, shingle and dunes") | nearly nothing until August, then the richest flow there is | cliff; burrow; the dry mound | shrike, praying mantis, bee-eater, bear |

★ marks the engine's eight keystones. Note where they fall: the village has
four, the moor two, the riverbank and the hedgerow one each, and the meadow
and the farm none. That is not designed; it is what the catalogue says, and
it is the right shape — the places a colony can live *through* a year are
the places people garden.

Two things the table exposes in the engine, to be settled before the world
leans on them. **Three species bloom in winter and winter's forage multiplier
is zero**, so a rosemary patch in January yields nothing today; the village
biome's whole character rests on those three, and the honest fix is a small
non-zero winter multiplier on a mild clear day, measured. And **the predator
roster is North American as much as British** — bear, raccoon, skunk,
opossum, termite mound — which the biome table can quietly make coherent by
assigning each to the ground it belongs on rather than pretending the game is
set anywhere in particular.

**Biomes modulate two dials the engine already has.** The threat system has
one line where a predator's daily chance begins (`ThreatSystem.encounterChance`)
and the disease system one function where a pathogen's arrival chance is
looked up; each biome supplies a multiplier per predator and per pathogen, and
nothing else in either system changes. A woodland is badger country; a
churchyard is wasp country; a wet burrow is nosema country. `HiveLocationType`
is untouched — the biome only decides *which* of the ten sites its features
can roll, and the site does the rest with the constants it already has.

## 5. Generation

Three noise fields, each a smooth value-noise function of cell position seeded
from the world seed: **wetness**, **openness** (trees to grass), and
**settlement** (how near people are). Biome is read off the first two with
settlement overriding — high settlement is village, moderate settlement on
open dry ground is farmland; wet is riverbank; wet-and-closed is not modelled
(no fen woodland in the catalogue); dry-and-open with low wetness is heath;
closed is woodland; open and moist is meadow; the boundaries between them are
hedgerow. Chunks are mostly one biome because the fields vary slowly; the
occasional chunk that straddles two is the more interesting one.

Within a chunk, **features** are placed from a per-biome list — a river
reach, a lane, an old oak, a barn, a church, a rock outcrop, an apiary, an
orchard corner — each at a probability, each occupying a cell or a line of
cells, and each carrying the 2023 idea: a probability of yielding a nest site,
and which `HiveLocationType` it yields. An old oak rolls for a living tree
cavity; a barn for a human structure; a church for inside walls; an outcrop
for a cliff; a river reach for a fallen tree along it. A chunk ends up with
none, one or two sites, and the player cannot see which until a scout or a
swarm has been there.

**Wild patches** are then placed per cell from the biome's species list with
the catalogue's rarity as the weight, sparsely — most cells are grass or
canopy with nothing to work — and made as `FlowerPatch` values with
`origin: .wild`, a `capacityScale` well below the photographed 1.0 (0.3 to
start, a number to measure), `registeredOnDay: nil` so they never fade, and
`distanceMetres` from their cell. They are shared with every other pollinator
in the country; that is what the scale represents. They regrow on the engine's
existing seasonal schedule and go out of bloom on the catalogue's calendar, so
the farm's rape is worth working for a fortnight and nothing after.

A flow, in this world, is a *place*: the willow along the river in March, the
rape field in May, the lime avenue in July, the moor in August. The colony's
year becomes a sequence of directions the dancers point in.

## 6. The garden

The garden is the ring of cells around the nest, and it is where photographs
go. Nothing about the core loop changes: the player photographs a real flower,
it is identified, it becomes forage. What changes is that it becomes forage
*somewhere* — in a cell of the garden, at 200 m, at a distance efficiency of
0.89 against the 0.67 every flower has had until now — and it is drawn there.

The garden is six cells to begin with. It grows with the milestones the game
already awards: ten flowers opens the second ring (twelve cells at 400 m),
ten families the third. The player chooses the cell when they plant, or lets
the game choose, and a cell can hold one patch, so a garden of thirty flowers
is a real plot with a shape, and its shape says something about the person —
the keystones close in, the summer plants out at the edge. When a patch fades
(60 days at full strength, 120 more to nothing, as now) its cell empties and
can be planted again.

Photographed flowers remain the *rich* forage. A garden patch has the full
photographed capacity with its identification bonus; a wild patch has a
fraction of it. That is the balance question at the centre of this design,
and it should be measured before anything else is built:

> With a generated world and no photographs at all, what is survival?

Today it is 0%, and PLAN.md calls photography load-bearing for that reason. In
a world with wild forage it will not be 0%, and it should not be — a wild
colony in a real hedgerow does not starve because nobody photographed
anything — but if it is 89% the photograph has stopped mattering and the game
has lost its premise. The target is somewhere a wild colony's real first year
sits, which PLAN.md notes is *far worse* than the 75% the game has been
quoting for established colonies: **40% first-year survival on wild forage
alone, and the garden is what lifts it to 89%.** `capacityScale` for wild
patches, and wild patch density, are the two levers, and `beesim --world`
(section 10) is how they are set.

The bloom prompt keeps its job with one change of tense: "Crocus is out now,
and your garden has none" becomes true of a garden with cells in it.

## 7. The fog

The world starts as the home chunk and the six around it, because a founding
swarm's scouts have already been over that much ground. Everything else is
unknown, and unknown is drawn as it would be on a good map that stops: paper,
with the range circle faintly across it so the player can see how much
country there is.

Chunks become known in four ways, and every one of them is a bee going there.

**Foragers.** When a colony works a wild patch, the chunk it is in becomes
known. Recruitment already reaches outward on its own: the dance weights every
patch in range by quality, so as the garden thins in a dearth the best thing
in range is further away, and the colony's foragers find it without being
told. A chunk the colony has never worked but which borders a known one shows
as *rumoured* — the dancers have pointed that way — with its biome guessed
from what the neighbours are and nothing else drawn.

*Built 2026-09-16, and with the trigger made explicit.* `ExplorationSystem`
runs daily after foraging and only when the colony **is in a dearth**, which it
asks `World.isInDearth` — the engine's own existing notion of being short,
rather than a new constant that would drift away from `dearthThresholdPerBee`.
A small share of the force (`explorationShare` 0.06) goes out; one rumoured
chunk is sampled from the seeded RNG in fixed order and discovered with a
probability proportional to how much wild forage is standing in it
(`explorationChance` 0.03), and nothing past the 8 km range is ever discovered.
The dearth condition is a deviation from the paragraph above, which implies
discovery simply follows from foraging: it is cheaper, it is deterministic, and
it means a fed colony stays home, which is what a fed colony does. At the
shipped defaults an instinct colony knows **7.7 chunks** after two years,
against the seven it was founded with — so exploration is a slow drift outward
and not a second pair of scouts.

**Scouts.** A decision, in the shape every other decision takes: during a
flow, when the colony can spare them, the game offers *send scouts* — a
tenth of the forager force for three days, which is honey not gathered — and
the ring of rumoured chunks around the known ones is revealed, sites and all.
Instinct, as always, is to do nothing, and a colony that never scouts still
finds what its foragers reach. This is the one new decision the world adds,
and it costs exactly what it says.

*Built 2026-09-16, exactly as written — and that is worth saying out loud,
because "the ring of rumoured chunks" is a great deal of ground.* A party
discovers **every** rumoured chunk on its return, so each time the decision is
taken the known world grows by a whole ring. A player who takes it every year
it is offered — `--policy scout`, six parties over two years — ends with about
**133 chunks** known against instinct's 7.7, which is most of the eight-kilometre
circle. That is what the design asked for, and it is also what made the decision
a trap before the dance was corrected: 260 stands in range, the force split
across all of them, and the colony starved with more forage available than any
colony in the game's history. Corrected, it costs **four points** of two-year
survival (64% against instinct's 68%) — a real price, one point past what
section 10 item 5 hoped for, and a price rather than a punishment.

**Swarms.** A swarm that leaves flies to a site. If the player follows it
(section 8), the chunk it settles in is known and the circle is drawn again
around the new nest. If the player does not, the swarm settles somewhere
rumoured and becomes a wild colony on the map, and the chunk is known by
that.

**Mating flights.** The research notes the game was built from say a queen
flies once in her life to a drone congregation area and that mating with
drones from other colonies improves resistance to disease. A DCA is a feature
some chunks carry. A virgin's flight reveals the chunk her DCA is in — the one
thing a queen ever sees of the world — and a colony within reach of a DCA
shared with another colony gets a small measured bonus to the genetics its
next queen comes back with. This is the last of the four and the least
necessary; it is here because the research supports it and nothing else in
the game gives a queen a reason to have a geography.

## 8. Colonising

This is where the world earns its place and where the engine changes most.

Today `World` holds one `Hive`, and following a swarm *replaces* the
simulation: the old colony ends, the new one starts with the old garden. In
the world, the map persists and colonies come and go on it.

**Following a swarm** becomes choosing a *site*: a known chunk with a cavity
in it, at a distance the swarm can fly. The site's `HiveLocationType` is
already decided by the feature that rolled it; the player is choosing between
the oak in the wood at two kilometres, the church wall in the village at
five, and the outcrop on the moor at seven — which is the new-colony screen
the game already has, with its three bars for room, warmth and safety, but
with the choice made *on the ground* and the ground deciding what the year
will be like. A swarm to the village wall will live through winter on
mahonia and be robbed by wasps; a swarm to the moor will have nothing until
August and then more than it can store. "Where the bees settle decides
almost everything" was true before; now the player can see why.

**The colony that stayed** does not vanish. It becomes a wild colony on the
map: not simulated hour by hour, because that is the cost the whole engine is
built to avoid, but given a fate each season from the measured survival
curves — the very tables in PLAN.md — adjusted by its site and biome. It
shows on the map with a state: thriving, quiet, gone. The player can go back
to it. Going back means a swarm from it, or from the current colony to it, or
— if it has died — its cavity is a site again, with the comb still in it,
which is how wild colonies actually get re-founded. Two things persist across
every colony the player ever has: the map, and the garden. The garden stays
where it was planted, so a player who follows a swarm two kilometres has
left their flowers behind at 2 km and starts a new garden ring by the new
nest, which is the real cost of moving and the reason a beekeeper does not.

**Several live colonies** is the later step, and its cost is known: a
colony-year is about 0.11 seconds on a desktop in release, so catching up
three colonies over the 180-day ceiling is under a second on a phone at
several times that. It is affordable. It is not free, and the watch's widget
extension is the binding constraint the code already names, so the widget
and the watch would show *one* colony — the one the player last looked at —
while the phone carries the rest. Phase 3, section 11.

## 9. The engine, concretely

Everything in this section lives in the package and is tested there. Nothing
in it needs an Apple framework.

- **`World` gains `terrain: Terrain?`**, decoded with `decodeIfPresent` in
  its hand-written `init(from:)` like every field added since the first save,
  so no old save fails to open. `Terrain` holds the world seed, the set of
  discovered chunk coordinates, the garden's planted cells, founded and wild
  sites, and nothing that can be regenerated. No format version moves; the
  two persistence regression tests from 2026-09-15 are the pattern to copy.
- **`FlowerPatch` gains `cell: HexCoordinate?`**, optional, safe in both
  directions, exactly as `registeredOnDay` and `storedOrigin` arrived.
  `PatchOrigin` gains `.wild`.
- **`Simulation.plant(_:at:)`** sets a patch's cell and recomputes its
  `distanceMetres`. Written 2026-09-15, and it is the first way there has ever
  been to move a patch after creation; it refuses an occupied cell.
  `registerPhotograph` takes an optional cell and derives distance from it when
  given, and places the patch itself in the first free cell in ring order when
  not — unless an explicit `distanceMetres:` is passed, which suppresses
  placement.
- **`WorldGenerator`**: `HexCoordinate` (axial q, r, with distance and
  neighbours), `Chunk`, `Biome`, `Feature`, `Site`, three value-noise fields,
  and `chunk(at:)`, pure and deterministic. Tested for determinism the way
  `DeterminismTests` tests the colony: same seed, same chunk, byte for byte,
  and different seeds differ.
- ~~**`ScoutSystem`**, a daily system after `ForagingSystem`, that spends the
  scouting force and reveals chunks~~ — built on 2026-09-16 as two things:
  `ExplorationSystem`, the daily system after `ForagingSystem` that sends a
  share of the force into rumoured ground when the colony is in a dearth, and
  `Simulation.sendScouts()`, the deliberate party the decision commits; the
  decision plumbing — `DecisionAction.scout`, the notification category, the
  intent, the widget's button, the watch's card — is in the shape the five
  existing decisions already have.
- **Biome multipliers** into the two hooks named in section 4, and nowhere
  else.
- **Wild colonies**: a `WildColony` record and a seasonal fate roll from
  survival tables that are themselves produced by `beesim`, so the coarse
  model is calibrated against the fine one rather than invented.
- **Migration of an old save**: a world seed derived from the colony's RNG
  state, the hive at the origin of a chunk whose biome is chosen to suit its
  existing site type, and every existing patch planted into the garden ring
  at 200 m. The colony gets *better* forage on migration; that is the honest
  consequence of a garden being next to the nest, and the baseline will be
  re-measured (section 10).
- **`beesim --world <seed>`** and `--biome <name>`: a trial colony in a
  generated chunk with wild forage, with or without the photographed patches
  the existing `--patches` and `--restock` supply; and `--policy scout`.

Three things the survey turned up that should be fixed *before* the world
starts creating patches in bulk:

- ~~`identifyPatch` rebuilds a patch and drops its `registeredOnDay`, `origin`
  and `sharedBy`, so a late identification makes a flower fresh again.~~
  **Fixed 2026-09-15**, in Phase 1, with a failing test first. It now preserves
  those three and `cell`, and restores `capacityScale` for a shared patch.
- ~~Forage space is handed out in patch insertion order rather than quality order
  when the colony is honey-bound, which a world that inserts wild patches ahead
  of the garden would turn into a visible bias.~~ **Fixed 2026-09-16**, in
  Phase 2, which is the phase that made it matter. Space now goes to candidates
  in descending `forageQuality` with ties broken by id. Measured alone with the
  world off: 66% to 66% at two years and 612 autumn stores to 613 — so the bias
  was never costing much, but the run is *not* byte-identical, which is the
  useful part: the colony is honey-bound often enough for the order to decide
  something.
- The winter bloom question above. **Decided 2026-09-24: winter forage
  exists**, at a multiplier set by measurement — the largest value that keeps
  the village within ten points of the next-best biome. PLAN.md section 3,
  "Decided by measurement", has the sweep.

## 10. What to measure, and the order to measure it in

1. **The baseline moves and must be re-taken.** A garden at 200 m has a
   distance efficiency of 0.89 against 0.67 at 800 m: the same photographs
   feed the colony a third better, before any wild forage. Run the standard
   `beesim` with `--distance 200` and see what 89/66 becomes; that is the new
   baseline, and everything below is measured against it.

   **Measured 2026-09-15**, on the clean tree before Phase 1 was written.
   Release build, 200 colonies, `--patches 9 --restock 45`:

   | `--distance` | year 1 | year 2 | swarms / 2 yr | autumn stores | winter cluster |
   |---|---|---|---|---|---|
   | 200 m | 86% | 66% | 2.99 | 749 | 362 |
   | 400 m | 89% | 66% | 2.49 | 612 | 313 |
   | 800 m | 86% | 54% | 1.19 | 392 | 172 |
   | `--world` (the garden) | 86% | 64% | 2.77 | 672 | 331 |

   Two findings came out of it. **The first is about the tool, not the world**:
   `beesim`'s `--distance` defaults to 400 m, so PLAN.md's recorded 89%/66%
   baseline was always a 400 m measurement — while a flower in the app sat at
   the nominal 800 m and therefore at 86%/54%. Nothing in the app was ever at
   400 m. The prediction at the head of this document, that every flower has sat
   at 0.67 distance efficiency, was right about the app and wrong about the
   trials.

   **The second is the one this section was written to catch.** Closer flowers
   buy stores and swarms, not survival: 200 m against 400 m is the same 66% at
   two years, with +0.5 swarms per colony per two years and +137 autumn stores,
   and three points *worse* in the first year. That is the
   abundance-breeds-swarms effect of section 1, at about the size section 1
   predicted, arriving before any wild forage exists. The garden lands between
   the 200 and 400 rows and nearer 400, for an arithmetic reason: nine patches
   plus restocks overflow ring 1 (six cells at 200 m) into ring 2 (twelve at
   400 m), so a colony's effective distance is a mix.

   So the new baseline is **86% first year and 64% second**, and that is what
   items 2 to 5 below are measured against. Whether it is the baseline the game
   should have is a calibration call, and it is in PLAN.md section 3 under "Not
   decided".

2. **Wild forage alone.** `beesim --world --patches 0`: survival with no
   photographs, per biome. Target 40% first year; set wild `capacityScale`
   and density to reach it.

   **Measured 2026-09-16.** The shipped answer is **46% first year**, at
   `wildPatchYield` 1.6 and `wildPatchDensity` 0.15 — about one stand to a
   parish. Density was the lever and yield was not: at 1.6 / 1.0 / 0.6 the
   answer is 64 / 59 / 60%, which is section 1's "more forage does not mean more
   survival" arriving from a new direction — income is bounded by foragers and
   flight time, not by what is standing. Density moved it properly: 0.4 → 64%,
   0.25 → 54%, 0.15 → 46%. 64% was rejected for a design reason rather than a
   measured one: it is close enough to what a garden gives that the photograph
   stops carrying the game. Whether 46 is the right floor is Kyle's, and it is
   in PLAN.md section 3 under "Not decided".

   **The per-biome table was taken at the earlier settings** — exponent 1,
   density 0.4, before the dance was corrected — and has *not* been re-taken at
   the shipped defaults, so read it for its shape and not for its numbers: wild
   alone, first year, meadow 46, hedgerow 42, woodland 10, riverbank 54,
   farmland 40, village 39, heath 38, mean 38.4%. Woodland at 10 against
   riverbank at 54 is the separation this design wanted; re-measuring it is a
   small item in PLAN.md section 3.
3. **Wild forage plus the garden.** `--world --patches 9 --restock 45`:
   should land near the re-taken baseline. If it is well above, wild forage
   is too rich; if colonies swarm far more than 2.49 per two years, that is
   the abundance-breeds-swarms effect and the design *wants* some of it — the
   question is how much, and PLAN.md's "whether the two-year cliff is where it
   should sit" is the same question.

   **Measured 2026-09-16: 90% first year, 68% second, 2.68 swarms per colony
   per two years, 926 autumn stores, 378 winter cluster.** That is a little
   above the Phase 1 baseline of 86/64 and a little above the world-off 400 m
   run, which the same day's foraging corrections took from 66% to 62%. The
   swarm rate is the effect this item was written to catch, and it is mild —
   2.68 against 2.49 — because the country is sparse and mostly further away
   than the garden. At the first tuning, before the dance was corrected, the
   same run measured 78%/56% with 1.69 swarms, which is *worse than the garden
   alone*: the country cost the colony until the recruitment slope was right.
4. **Biomes differ, and by the right amount.** A survival-by-biome table.
   The village should winter best and be robbed most; the moor should be a
   gamble that pays in autumn; the wood should be safe and hungry. If the
   biomes do not separate by at least ten points, the multipliers are too
   timid to be worth having.

   **Measured 2026-09-16, at the earlier settings — exponent 1, density 0.4 —
   and not re-taken since**, so this too is a shape rather than a set of
   numbers. With the garden on, at two years: heath 42, meadow 50,
   riverbank 54, farmland 55, hedgerow 57, woodland 60, village 64. A 22-point
   spread, against a floor of ten, so the multipliers were left where they
   were and nothing was widened. The village winters best, as designed; heath
   is the gamble and it loses more often than it wins. `biomeThreatScale` is
   the one dial over all of it — 1.0 as shipped, 0 to switch the whole effect
   off, which is what the threat tests use so that they measure sites rather
   than geography.
5. **Scouting is worth its cost, and only just.** `--policy scout` against
   instinct, as every decision has been measured. Two or three points is
   right; ten means a colony that never scouts is being punished for the
   player's absence.

   **Measured 2026-09-16: 64% against instinct's 68% at two years, with 2.35
   swarms against 2.68 and 133 chunks known against 7.7.** A four-point price,
   one point past what this item hoped for, and worth leaving there until
   somebody decides the price is wrong. This is the measurement the whole phase
   turned on: at the first tuning it was **2%**, and the diagnosis is in
   section 1 above and in PLAN.md's "the country". A decision measuring at 2%
   was not a decision that needed tuning — it was the first thing in the game
   ever to ask the dance about distance, and the dance had the wrong answer.

6. **Determinism.** Two runs, a diff, nothing printed — with the world on.

   **Checked 2026-09-16**: two `--world` runs of the built binary diff to
   nothing. And leaving `--world` off now forces `wildPatchDensity = 0`, so
   every `--distance` baseline ever recorded stays comparable with every later
   one.

## 11. Phases

**Phase 1 — the ground. Built 2026-09-15**, the day this document was written.
`HexCoordinate`, the generator, `Terrain` on `World`, patches with cells, the
garden ring, distance live, the World tab drawing the home chunk and its six
neighbours, migration of the existing save, `beesim --world`, and the re-taken
baseline. No fog, no scouts, no wild forage yet — the map shows the garden as a
place. This is the phase that changes the numbers and it was measured alone: the
table under item 1 above was taken on the clean tree first, the engine is
byte-identical with the world off, and `--world` run twice diffs to nothing. The
package half is done and tested; the World tab is the app half and is not
verified here. PLAN.md's "the ground" entry is the full record.

Four deviations from this document, each deliberate:

- **`newGame` always creates terrain**, where section 9 above had it arriving
  only under `--world`. A colony without terrain is a colony whose flowers are
  all at 800 m, and there is no reason to ship two worlds.
- **An explicit `distanceMetres:` suppresses garden placement entirely.** A
  caller naming a distance is saying where the flower is. This is what keeps a
  `beesim` sweep at one distance, and it is what made the world-off runs
  byte-identical.
- **Migration skips faded patches.** The free-cell search ignores them, so two
  faded patches would otherwise be handed the same cell.
- **Migration lives in persistence, not in the store.**
  `Simulation.adoptTerrainIfMissing()` is called from `GamePersistence.load()`
  and `decodeTransfer(_:)`, because the widget, the complication, the App
  Intents, `WatchLink` and `BackgroundRefresh` all open the save directly and
  would otherwise show a different colony from the phone.

And one thing the measurement found that has nothing to do with the world:
**`beesim`'s default `--distance` is 400 m, not the nominal 800 m the app
uses**, so every balance number recorded since 2026-09-06 was taken a ring
closer than the game was played. See item 1 above and PLAN.md section 1.

**Phase 2 — the country. Built 2026-09-16.** Wild stands generated per chunk
and registered only when the chunk is discovered, the fog in three states,
`ExplorationSystem`, scouts as the game's sixth decision, biome multipliers at
the two hooks section 4 names, the bloom prompt with a direction in it, and the
World tab drawing all of it. All six of section 10's measurements were taken and
are recorded there; the phase cost three corrections to the foraging model
before any of them could be believed, and PLAN.md's "the country" is the full
record. The package half is tested; the app half is not verified here beyond a
simulator.

Four deviations from this document, each deliberate:

- **Exploration is triggered by a dearth**, where section 7 above has chunks
  becoming known simply because a forager worked one. `World.isInDearth` is the
  engine's own notion of being short and does not drift from
  `dearthThresholdPerBee`; a fed colony stays home, which is what a fed colony
  does; and it is cheap and deterministic. It drifts outward slowly — 7.7 chunks
  known after two years, from seven at founding.
- **`danceFloorPatches = 16`.** Nothing in this document anticipated that a
  colony might have 260 stands in range and split its force across all of them
  and die. The dance now recruits onto the best sixteen only, which is above
  anything the game produced before the world existed.
- **`danceDistanceExponent`, defaulting to 3.0.** The correction in section 1
  above, and the largest single thing this phase changed. It is a change to the
  model rather than to the world, and it leaves every world-off number ever
  recorded untouched.
- **Density 0.15, not the "`capacityScale` and density" pair section 10 item 2
  proposed tuning together.** Yield turned out not to be a lever at all — 1.6,
  1.0 and 0.6 give 64, 59 and 60% — so it stayed at 1.6 and density did the
  whole job.

And two things this phase forced that have nothing to do with the world: a
forager whom a stripped patch cannot serve now follows the next dance rather
than not foraging at all, and forage space goes out in quality order (section 9
above). Together those cost four points of world-off two-year survival, 66% to
62%, and that is a correction rather than a tuning.

**And one finding nothing in this document predicted.** A better-fed colony
rears more brood and therefore carries more mite:
`VarroaTests.testVarroaBuildsTowardDamagingLevels` failed at 0.327 against its
0.3 one-year ceiling the moment the fixture colony had wild stands. The test now
pins `wildPatchDensity = 0`, because it is about mite dynamics on a known
colony; the finding — **wild forage brings varroa on sooner** — is real and has
not been measured at any scale beyond that one test.

**Phase 3 — colonising.** Following a swarm to a site on the map; wild
colonies with seasonal fates; going back; the garden left behind.

**Phase 4 — if it earns it.** Several live colonies; drone congregation
areas; the farmer as a hazard with a season (the research lists pesticides
among the real threats to bees, and a farm chunk is where it would live); an
apiary as a competitor that robs and is robbed.

## 12. What the player sees

A fifth tab is one too many, so the World replaces nothing and takes the
Forage tab's old slot: **Colony, Nest, World, Garden**. The Garden stays what
it became today — the collection, the calendar, the record that outlives any
colony — and the World is where that collection is *planted*. The map is a
SwiftUI `Canvas` of hexagons coloured by biome, drawn the way the app icon is
drawn — from a script, in the honey palette, with no art assets to
commission — flowers as marks in their cells, the nest, the sites, the
range circle, and paper past the edge. Tapping a cell says what grows there
and what is working it; tapping a site says what it would be like to live in.
Season tints the whole thing: the rape field is only yellow in May. The watch
shows nothing of it; the widget, at most, a direction the foragers are flying.

## 13. Not proposed, and why

- **Real geography, in any form.** Removed today because it turns people
  away; a fictional world asks for nothing and gives the same mechanic more.
- **Building things.** Hives, fences, water troughs, upgrades. These are
  wild bees; the player photographs and answers, and plants — and planting is
  as far as building goes.
- **A defence minigame, or resource-gathering by hand.** The 2023 game, for
  the 2023 reason.
- **Trading, servers, a shared world.** Flowers and swarms already travel
  between players as files. A friend's swarm settling in your map, from a
  `.swarm` file, is the multiplayer this needs and it already works.

## 14. Decisions for Kyle

- Whether wild forage should be able to keep a colony alive at all without
  photographs, and at what floor. The design says 40% and says why; it is
  the identity question and it is yours.
- The tab structure — World in the Forage slot, or the World subsuming the
  Garden.
- Whether colonies the player leaves persist as wild colonies on the map, or
  simply end as they do now. The design wants them to persist; it is the
  bigger build.
- ~~The predator roster's nationality.~~ Decided 2026-09-24: assigned to
  biomes, and the game is nowhere in particular — it no longer knows where
  the player is, since location was removed. PLAN.md section 3 has the
  reasoning.
- ~~Whether winter forage should exist.~~ Decided 2026-09-24: it does. Three
  keystone species and a whole biome said yes, and the balance has now been
  measured with it on; see PLAN.md.
