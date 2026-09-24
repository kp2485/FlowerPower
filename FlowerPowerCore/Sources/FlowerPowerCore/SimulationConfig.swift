//
//  SimulationConfig.swift
//  FlowerPowerCore
//
//  Every balance number the engine uses, in one place, so tuning never means
//  hunting through system code. Rates are per bee per tick (one simulated
//  hour) unless the name says otherwise.
//
//  # Units
//
//  One honey unit is roughly a gram. One "bee" is a cohort rather than a
//  literal insect â€” a real colony peaks near fifty thousand workers, which no
//  phone wants to render â€” so the site capacities here (a few hundred cells)
//  represent a full-sized nest. Rates were then derived from the real ratios
//  and scaled to that cohort, targeting:
//
//    - a mature colony of roughly 300-500 bees
//    - about 20 honey per day gathered at the height of the flow
//    - about 6 honey per day consumed by a wintering cluster
//    - roughly 450 honey needed to see a colony through winter
//
//  Those four numbers are what the rest of this file is solving for. Changing
//  one in isolation will pull the colony out of balance; the long-run tests in
//  `ViabilityTests` are what catch it when that happens.
//

import Foundation

public struct SimulationConfig: Codable, Equatable, Sendable {

    // MARK: - Foraging

    public var nectarPerForager: Double = 0.075
    public var pollenPerForager: Double = 0.06
    public var waterPerCarrier: Double = 0.05
    public var propolisChance: Double = 0.004

    /// Honey burned per forager per tick, before the distance multiplier.
    public var flightEnergyPerForager: Double = 0.0015

    /// Wear accrued per tick of foraging. Foraging, not calendar age, is what
    /// actually ends a worker's life: at this rate a bee that forages every day
    /// dies around a third sooner than one that never leaves the nest.
    ///
    /// This trades directly against colony viability. Set too high, a worker
    /// wears out before she has gathered back what it cost to rear her, and the
    /// colony shrinks no matter how good the forage is.
    public var forageWearPerTick: Double = 0.03

    /// Exponent applied to patch quality when allocating foragers. Above 1 the
    /// colony concentrates on its best forage, which is what the waggle dance
    /// achieves in a real hive.
    public var danceRecruitmentExponent: Double = 1.6

    /// Fraction of a patch's capacity that regrows each day while in bloom.
    public var patchDailyRegrowth: Double = 0.18

    /// Winter's forage, as a multiplier standing where `Season.forageMultiplier`
    /// and `Season.patchRegrowthMultiplier` have autumn's 0.65 and 0.35.
    ///
    /// It was zero until 2026-09-24, and three keystones bloom in winter —
    /// crocus, winter heather and mahonia — so none of them did anything and
    /// the village, whose whole character is that something is out all year,
    /// was no different from the moor in the season that kills colonies. It
    /// applies only to a stand that is in bloom in winter, and only on a day
    /// the bees can fly, which in a winter averaging 2°C the weather already
    /// makes rare and cold; nothing else about winter changes.
    ///
    /// The value is `shippedWinterForage`; the sweep that chose it is there.
    /// Stored as an optional so that a save does not pin the colony to
    /// whatever the value was when it was written. (It was first made optional
    /// so that a save written before it existed would decode, back when the
    /// config was decoded by synthesis; `init(from:)` below now does that for
    /// every key.) Nil is the shipped value; `beesim --set
    /// winterForageMultiplier=` sets it.
    public var winterForageOverride: Double? = nil

    /// What winter's forage actually is: the override where one is set, and
    /// the shipped value otherwise.
    public var winterForageMultiplier: Double {
        winterForageOverride ?? Self.shippedWinterForage
    }

    /// Chosen by measurement on 2026-09-24: 200 colonies, two years, the world
    /// on with the standard garden, swept over 0 (as it was), 0.15, 0.3 and
    /// 0.5, the generated world and then each biome forced in turn. The rule
    /// was the largest value at which the village's two-year survival does
    /// not exceed the best other biome's by more than ten points.
    ///
    ///     two-year survival   0     0.15  0.3   0.5
    ///     standard world      68%   67%   68%   67%
    ///     village             68%   68%   69%   68%
    ///     best other biome    68%   68%   68%   68%   (hedgerow, meadow, riverbank)
    ///
    /// No value came near the limit, so it ships at the top of the sweep. The
    /// honest reading of the table is that winter forage barely moves the
    /// colony at all: a winter bloomer can only be worked on a day warm enough
    /// to fly, after the cluster has loosened, and the only ones a `beesim`
    /// colony meets are the country's sparse wild stands — the trial garden's
    /// palette has none. The village took in about 40 more units of nectar
    /// over two years at 0.5 and its autumn stores rose from 947 to 955. The
    /// player who photographs a mahonia is who this is for, and that is not a
    /// row this sweep had.
    ///
    /// 0.5 is above autumn's regrowth multiplier of 0.35, which is worth
    /// knowing before anybody reads it as "winter regrows faster than
    /// autumn": in the seasons' own terms it is under autumn's 0.65 for what
    /// a forager brings home, and the weather gates it far harder.
    public static let shippedWinterForage: Double = 0.5

    /// How much the landscape offers in a season: `Season.forageMultiplier`,
    /// with winter's taken from `winterForageMultiplier`.
    public func forageMultiplier(in season: Season) -> Double {
        season == .winter ? winterForageMultiplier : season.forageMultiplier
    }

    /// How fast a stand in bloom refills in a season:
    /// `Season.patchRegrowthMultiplier`, with winter's taken from
    /// `winterForageMultiplier`.
    public func patchRegrowthMultiplier(in season: Season) -> Double {
        season == .winter ? winterForageMultiplier : season.patchRegrowthMultiplier
    }

    /// Days of brood feeding the colony wants banked as pollen and bee bread
    /// before its foragers lose interest in pollen and switch to nectar.
    public var pollenReserveDays: Double = 8
    /// Pollen a colony keeps on hand even with no brood at all.
    public var minimumPollenReserve: Double = 60

    // MARK: - In-hive processing

    /// Nectar is mostly water; roughly three units reduce to one of honey.
    public var nectarPerHoney: Double = 3.0
    public var honeyPerConcentrator: Double = 0.03

    public var beeBreadPerPacker: Double = 0.014
    public var honeyPerBeeBread: Double = 0.35
    public var pollenPerBeeBread: Double = 0.8

    public var royalJellyPerNurse: Double = 0.014
    public var honeyPerRoyalJelly: Double = 0.45
    public var pollenPerRoyalJelly: Double = 0.35

    /// Days of food the colony tries to keep ahead of demand. Without a buffer,
    /// production oscillates; with too large a buffer, perishables are wasted.
    public var foodBufferDays: Double = 1.5

    // MARK: - Wax and comb

    /// Features.md: six to eight pounds of honey per pound of wax. Kept at the
    /// real ratio; the absolute cost is set by `CellType.waxCost`.
    public var honeyPerWax: Double = 7.0
    public var waxPerBuilder: Double = 0.004
    public var cellsPerBuilderPerTick: Double = 0.01

    /// Comb is only drawn once the drawn comb is this full.
    public var buildCongestionThreshold: Double = 0.55
    /// Honey the colony refuses to spend on wax, whatever the demand.
    public var buildHoneyReserve: Double = 25

    /// The share of a day's *surplus income* a colony will turn into wax.
    ///
    /// Comb is built out of the flow, not out of the larder. That is what
    /// `ConstructionSystem`'s own header has always said — "no flow, no drawn
    /// comb, no matter how much foundation you give them" — but the code
    /// gated on a flow being *on* and then spent everything above
    /// `buildHoneyReserve`, which for an overwintered colony is its entire
    /// standing store.
    ///
    /// Traced on seed 32676. A colony came out of winter with 60 bees and 107
    /// units, met a day or two of willow, and spent 71 of those units drawing
    /// 127 cells it had no bees to fill. It starved on day 416 in the middle
    /// of spring, with its brood, at full vitality a fortnight earlier. Six
    /// more colonies in the same 60 did the same thing within a fortnight of
    /// each other.
    ///
    /// Three quarters, which is the honest reading of what a congested colony
    /// does with nectar it has nowhere to put: most of it becomes room, and
    /// the rest goes on the brood being fed out of the same flow.
    ///
    /// Not fitted to a target. Over 200 colonies the two-year survival across
    /// 0.5, 0.75 and 1.0 is 50%, 54% and 56%, which is inside the spread of a
    /// 200-colony sample, so the exact value is not what the improvement rests
    /// on. (At 60 colonies the same sweep looked like a step from 45% to 60%
    /// between 0.7 and 0.8. It was noise, and it is the reason the number
    /// above comes from 200.)
    public var waxIncomeShare: Double = 0.75
    /// Bees cannot secrete wax below this nest temperature.
    public var minimumWaxTemperature: Double = 30

    /// Cells one adult bee can keep patrolled and clean.
    public var cellsMaintainedPerBee: Double = 9.0
    /// Fraction of unmaintainable comb lost per day.
    public var combDecayRate: Double = 0.04

    // MARK: - Consumption

    public var honeyPerAdult: Double = 0.0006
    public var foodPerLarva: Double = 0.002
    /// Larvae are fed royal jelly for their first days, then bee bread.
    public var royalJellyDays: Int = 3

    public var queenRoyalJellyPerDay: Double = 0.15
    public var queenCellRoyalJellyPerDay: Double = 0.3

    /// Days of royal jelly the colony keeps standing for the queen and her
    /// cells.
    ///
    /// Without a reserve the supply is bang-bang: nurses secrete exactly one
    /// day's worth, the queen eats it, spoilage takes the rest, and she spends
    /// half her life technically underfed. Her condition then oscillated
    /// between 0.1 and 1.0 from day to day, and since lifespan scales with
    /// condition she died whenever the check happened to land on a bad day —
    /// at around thirteen months instead of two years.
    public var queenJellyReserveDays: Double = 2

    /// Per-tick chance a starved queen cell is torn down. Small: this is
    /// evaluated twenty-four times a day, and a cell has to survive twelve days.
    public var queenCellAbandonChancePerTick: Double = 0.002

    /// Condition lost per tick while underfed.
    public var starvationDamagePerTick: Double = 0.02
    public var malnutritionDamagePerTick: Double = 0.015
    public var broodRecoveryPerTick: Double = 0.004
    /// The queen is fed by attendants before anyone else eats, so she loses
    /// condition slowly and regains it readily.
    ///
    /// With the general starvation rate applied to her, an occasional shortfall
    /// eroded her permanently â€” damage outran recovery ten to one, her
    /// effective lifespan fell from two years to about thirteen months, and
    /// colonies lost their queen in their second spring while broodless and
    /// unable to raise another.
    public var queenStarvationDamagePerTick: Double = 0.003
    public var queenRecoveryPerTick: Double = 0.010

    /// Fraction of starving brood lost per tick.
    public var broodStarvationRate: Double = 0.03
    /// Fraction of starving adults lost per tick once hunger is severe.
    public var adultStarvationRate: Double = 0.01

    // MARK: - Thermoregulation

    public var targetTemperature: Double = 35.0
    /// A broodless winter cluster runs far cooler, and far cheaper.
    public var broodlessClusterTemperature: Double = 20.0
    public var minimumBroodTemperature: Double = 32.0
    public var safeTemperatureBand: Double = 2.0
    public var targetHumidity: Double = 0.6

    /// How fast nest temperature bleeds toward ambient, before insulation.
    public var thermalLeakRate: Double = 0.08

    /// Degrees per tick one bee can add by shivering.
    ///
    /// Generous by design. A literal six-bee colony could not thermoregulate at
    /// all, and the founding colony from Features.md is six bees â€” so the
    /// cohort abstraction is doing real work here. Heating is capped by the
    /// actual deficit, so a large colony gains nothing from the headroom.
    public var heatingPerAdult: Double = 0.12
    /// Honey burned per degree per bee. The dominant winter expense, and the
    /// number that decides whether a colony sees spring.
    public var honeyPerDegreeHeating: Double = 0.0012

    public var coolingPerFanner: Double = 0.05
    public var waterPerDegreeCooling: Double = 0.15

    /// Brood lost per tick per degree outside the safe band.
    public var broodLossPerDegree: Double = 0.004
    /// Condition lost by surviving brood, per degree, per tick.
    public var broodDamagePerDegree: Double = 0.003

    // MARK: - Queen and brood

    public var maxEggsPerDay: Int = 26
    /// Nurses required to support one egg per day.
    public var nursesPerEgg: Double = 1.2
    public var droneEggShare: Double = 0.10
    public var droneRearingMinimumPopulation: Int = 60
    public var droneEvictionChance: Double = 0.3

    /// Edible energy below which the queen stops laying entirely.
    public var layingEnergyThreshold: Double = 8

    /// Working reserve a colony keeps back per adult bee before committing
    /// stores to brood, in spring and summer.
    ///
    /// The floor used to be `layingEnergyThreshold` alone — a flat 8 units
    /// whatever the size of the colony. Eight units is a fortnight's food for
    /// a nucleus and rather less than a day's for a colony of six hundred, so
    /// a big colony would rear brood until the stores were gone and then
    /// starve with a nest full of larvae it could not feed. Traced on seed
    /// 8919: 615 bees on day 410, honey at 14 and falling, dead by day 440
    /// in the middle of spring.
    ///
    /// Real colonies hold back in proportion to their size, and a strong
    /// colony in a June gap is exactly the one a beekeeper worries about.
    /// 0.20 is about a fortnight of food per bee at `honeyPerAdult`, which is
    /// the sort of buffer a colony deciding whether to expand actually keeps.
    /// Measured: at 0.06 two-year survival is 13%, at 0.20 it is 30%, and past
    /// that colonies grow too cautiously to swarm.
    public var layingReservePerBee: Double = 0.20

    /// Fraction of the spendable reserve the colony will commit to brood each
    /// day. Higher makes colonies gamble their stores on expansion; lower makes
    /// them hoard and grow slowly.
    public var broodReserveDrawRate: Double = 0.035

    /// Multiplier on raw larval food cost, covering the honey and pollen burned
    /// turning stores into royal jelly and bee bread.
    public var broodFoodOverhead: Double = 1.8

    /// How much of the autumn flow still to come the colony is willing to bank
    /// on when sizing its winter cluster. Below 1 it is cautious; above 1 it
    /// gambles on a good ivy flow that may not arrive.
    public var autumnIncomeOptimism: Double = 0.2

    /// Safety margin the colony builds into its winter provisioning. Above 1 it
    /// rears a smaller cluster than its stores strictly allow â€” which is what a
    /// colony facing an uncertain winter should do, and the difference between
    /// mostly surviving and mostly starving in March.
    public var winterProvisioningMargin: Double = 1.0

    /// Point through winter at which the colony starts rearing again, as a
    /// fraction of the season. Earlier means a stronger spring but a heavier
    /// draw on stores that still have to last.
    public var winterBuildUpStart: Double = Season.winterDormancyEnds + 0.05

    /// Open brood one nurse can actually feed. Brood beyond this starves
    /// however much food is in store, because the jelly has to come out of a
    /// nurse's glands.
    /// Lower than it looks, because the nurse pool now includes the whole
    /// winter cluster: winter bees retain their brood-food glands, so a
    /// wintered colony counts as far more nurses than its age profile suggests.
    public var broodPerNurse: Double = 2.0

    /// Vitality below which the colony considers the queen to be failing.
    public var queenFailureVitality: Double = 0.32
    /// Fraction of her lifespan past which supersedure becomes likely.
    public var queenSupersedureAge: Double = 0.65
    /// Daily chance a colony with a failing queen commits to replacing her.
    /// Kept low: every supersedure gambles the colony on a virgin queen
    /// surviving her mating flight, so frequent supersedure is itself lethal.
    public var supersedureChance: Double = 0.02
    public var maximumQueenCells: Int = 6

    /// Cells a queenless colony starts at once. A colony that has just lost its
    /// queen does not politely raise one candidate a day â€” it converts every
    /// suitable larva it can reach, because most of those cells will fail.
    public var emergencyQueenCellBurst: Int = 3

    public var matingFlightEarliestDay: Int = 6
    public var matingFlightLatestDay: Int = 30
    public var matingFlightMinimumTemperature: Double = 18
    public var matingFlightPredationChance: Double = 0.045
    public var baseDroneEncounters: Double = 14

    public var layingWorkerOnsetDays: Int = 24
    public var layingWorkerEggsPerDay: Int = 8

    /// Daily nectar per adult bee above which the colony behaves as though it
    /// is in a flow: drawing comb, rearing hard, and considering swarming.
    ///
    /// Sweepable because it is expressed in forage units, and those units
    /// changed meaning when nectar stopped being an abstract richness number
    /// and became sugar yield derived from corolla depth, volume and sugar
    /// concentration. A threshold in a unit that has been redefined has to be
    /// re-measured, not carried across.
    public var flowThresholdPerBee: Double = 0.20

    /// Below this the colony is in dearth: brood rearing stops, drones are
    /// evicted, and robbing begins.
    public var dearthThresholdPerBee: Double = 0.04

    // MARK: - Decisions

    /// Propolis it takes to narrow the entrance for winter.
    public var entranceSealPropolis: Double = 6

    /// A sealed entrance keeps mice out: their encounter chance is multiplied
    /// by this. It also keeps damp in, which is `sealedEntranceDiseaseFactor`.
    public var sealedEntranceMouseFactor: Double = 0.15
    public var sealedEntranceDiseaseFactor: Double = 1.08
    /// And it keeps warmth in, which is the reason to do it.
    public var sealedEntranceHeatRetention: Double = 0.9

    /// How far discouraging a swarm lowers its chance of going, 0...1. A
    /// beekeeper giving room does not stop a colony that has decided; it
    /// changes the odds.
    public var swarmDiscouragementEffect: Double = 0.5

    /// How much of a normal patch a *shared* flower is worth. One. A flower
    /// somebody sends you is worth exactly what a flower is worth.
    ///
    /// This was briefly 0.7, on two arguments that both turned out to be
    /// wrong. The knob is kept, at 1, so that the next person to have the same
    /// idea finds the measurement instead of the intuition.
    ///
    /// The first argument was balance: a penalty would stop a well-connected
    /// player from skipping the core loop. Measured over 60 trials, a colony
    /// fed entirely by shared flowers survives at 77-82% against 75% for one
    /// fed by the player's own photographs — and it still does at a yield of
    /// 0.5. The penalty did not do the thing it existed to do, because
    /// survival is bounded by comb space and colony dynamics rather than by
    /// how much forage is on offer.
    ///
    /// The second was thematic: a shared flower is second-hand information,
    /// like a forager recruited by a waggle dance rather than a scout who
    /// found the patch herself. But recruitment is *already* modelled, in
    /// `ForagingSystem`, and applies to every patch the same way. Charging a
    /// shared patch again for it was double-counting a mechanic the engine
    /// already has.
    ///
    /// What is left is a patch of clover, which is a patch of clover. Somebody
    /// went outside and found it; that it was not you does not change what is
    /// in the flower. A gift that arrives worth less than the real thing is
    /// also a poor gift, and the point of sharing is to genuinely feed
    /// somebody's bees.
    ///
    public var sharedPatchYield: Double = 1.0

    // MARK: - The country

    /// How much of a photographed patch a *wild* stand is worth.
    ///
    /// The number `WORLD.md` section 6 puts at the centre of the whole design.
    /// A photograph is a flower the player went out and found, and it feeds
    /// the colony at full capacity with the identification bonus on top; a
    /// wild stand is a hedge shared with every other pollinator in the parish,
    /// and this is that share. Set it too high and the photograph stops
    /// mattering and the game loses its premise; set it to zero and a wild
    /// colony in a real hedgerow starves, which is not true of wild colonies.
    ///
    /// The target it is set against is 40% first-year survival on wild forage
    /// alone, measured with `beesim --world --patches 0`, against 86% with the
    /// garden. Multiplied by `Biome.wildAbundance` and by the stand's own
    /// variation, so this is the world-wide dial and the biome table is the
    /// shape.
    ///
    /// **Measured, and it only pays alongside a low density.** 200 colonies,
    /// one year, wild forage alone, at the density the biome table names: 0.3
    /// gives 26%, 0.8 gives 33%, 1.6 gives 33% — it saturates, because the
    /// colony's income is bounded by how many foragers it has and how far they
    /// fly rather than by what is standing there. Halve the number of stands
    /// and raise this to 1.6, and the same measurement gives 38%: *fewer and
    /// richer* beats *more and thinner* on both sides of the balance. See
    /// `wildPatchDensity` for why.
    ///
    /// A wild stand at 1.6 is a little richer than a photographed flower's
    /// 1.36, and that is not the contradiction it looks: a stand is shared
    /// with every other pollinator in the parish and stands where it stands,
    /// which at 800 m and beyond is worth a third less per trip than a
    /// photograph planted at 200. The photograph is still worth 25 points of
    /// first-year survival and 30 at two years.
    public var wildPatchYield: Double = 1.6

    /// How much more steeply *recruitment* falls off with distance than yield
    /// does. An exponent on the patch's distance efficiency, in the dance and
    /// nowhere else.
    ///
    /// The harvest keeps the plain efficiency: a bee who flies two kilometres
    /// still brings back what two kilometres is worth. What changes is whether
    /// anybody follows the dance at all. Seeley's finding is that a distant
    /// source has to be *much* more profitable before it recruits — the dance
    /// threshold rises with distance far faster than the yield falls — and the
    /// engine had the two at the same slope, which is why an untouched stand a
    /// kilometre out out-ranked a half-worked garden patch at the door.
    ///
    /// Three, from a sweep on 2026-09-16 over 200 colonies and two years, with
    /// the garden on. At one — the engine as it was — the country *cost* the
    /// garden colony (56% against 62% with the garden alone) and a colony that
    /// scouted survived at 2%: it abandoned its worked garden for untouched
    /// stands miles out and starved. At two, 64% and 55%. At three, 69% and
    /// 66% — scouting a three-point price rather than a trap, and the country
    /// worth having. Wild forage alone rose with it (38% → 64% first year),
    /// which is a matter for `wildPatchDensity` rather than a reason to
    /// flatten the dance again.
    ///
    /// A run with the world off is byte for byte what it was at any exponent:
    /// its patches all stand at one distance, so the factor is the same on
    /// every weight and cancels when the shares are normalised. Measured, not
    /// assumed — the 400 m baseline diffs clean at one and at three.
    public var danceDistanceExponent: Double = 3.0

    /// How many patches the dance floor holds: the best this many, and nothing
    /// else gets a dancer.
    ///
    /// **The single most important number the country added, and it is about
    /// the colony rather than about the ground.** Recruitment was spread over
    /// every patch in bloom, weighted by quality — which is fine for the nine
    /// or twelve flowers a player photographs and catastrophic for a
    /// countryside. A colony that had scouted the whole eight-kilometre circle
    /// held two hundred and sixty stands, split its force across all of them,
    /// and died: every colony of two hundred, in the first year, with more
    /// forage on offer than the game has ever had. Abundance was a *penalty*,
    /// which is the exact opposite of what `docs/WORLD.md` section 1 says the
    /// world is for.
    ///
    /// A real dance floor is not two hundred and sixty sources either. Recruits
    /// follow the most vigorous dances; a marginal source gets watched and
    /// ignored. Sixteen is a colony's working repertoire, and it is above
    /// anything the game produced before the world existed — nine photographs
    /// and their restocks — so a colony with no country behaves exactly as it
    /// always did. The ranking is recomputed every tick, so a patch that is
    /// worked down drops off the floor and the next one steps up: the floor
    /// rotates, it is not a fixed list.
    public var danceFloorPatches: Int = 16

    /// How thick the country is, as a multiplier on each biome's own count of
    /// wild stands per 37-cell chunk.
    ///
    /// The second of the two levers `docs/WORLD.md` section 6 names, and the
    /// one that turned out to decide the whole thing — downward.
    ///
    /// **Forty stands are worse than sixteen, on both sides of the balance.**
    /// The dance recruits on quality, and quality is a profitability rather
    /// than an amount: a full stand at 900 m rates above a half-worked garden
    /// patch at 200, so a thick countryside pulls the colony's force outward,
    /// where every trip returns less and costs more honey to fly. Measured
    /// over 200 colonies with the standard garden: at the biome table's own
    /// density the first year is 63%, at 0.4 of it 80%, against the 86% of a
    /// colony with no country at all. And on wild forage alone, 0.4 with the
    /// yield raised to match gives 38% where the full density gives 33%.
    ///
    /// It shipped at 0.4 — about two stands to a parish — while the dance was
    /// flat with distance. Once `danceDistanceExponent` went to three, a colony
    /// with no photographs at all survived its first year 64% of the time at
    /// that density, which is too close to the 90% a garden gives it: the
    /// photograph has to be the thing that matters. Measured on 2026-09-16,
    /// 200 colonies, wild forage alone: 0.4 → 64%, 0.25 → 54%, 0.15 → 46%.
    /// Yield was not the lever — 1.6, 1.0 and 0.6 all landed within five
    /// points — because income is bounded by foragers and flight, not by
    /// what is standing. So it ships at 0.15, about one stand to a parish,
    /// and the country is sparse the way real country is: most cells are grass
    /// or canopy with nothing in them for a bee.
    public var wildPatchDensity: Double = 0.15

    /// How far the biome tables are allowed to move a threat, as a multiplier
    /// on their deviation from one.
    ///
    /// One is the tables as written. Zero switches biomes out of the threat
    /// and disease systems entirely and is the row every measurement of them
    /// is taken against — `beesim --set biomeThreatScale=0` is the engine
    /// before `WORLD.md` section 4 existed. Above one widens the spread
    /// between biomes without editing fourteen numbers.
    public var biomeThreatScale: Double = 1.0

    /// The share of the forager force a scouting party takes, and how long it
    /// is gone.
    ///
    /// A tenth for three days, which is what `WORLD.md` section 7 says the
    /// decision costs: honey not gathered, in exchange for the ring of
    /// rumoured ground being drawn. The cost is the whole point of it being a
    /// decision rather than a button.
    public var scoutShare: Double = 0.10
    public var scoutDays: Int = 3

    /// The share of the force that wanders when the colony is short, and how
    /// readily a wandering forager comes back having found somewhere.
    ///
    /// Much smaller than a scouting party, because this is not a decision and
    /// nobody sent them: it is what a dearth does to foragers on its own,
    /// which is push them further out. `explorationChance` multiplies a
    /// rumoured chunk's standing wild forage, so an empty parish is very
    /// rarely found and a field of rape usually is.
    public var explorationShare: Double = 0.06
    public var explorationChance: Double = 0.03

    /// Days a photographed patch holds full strength before it starts to go.
    ///
    /// Sized against the seasons rather than against real time: 60 is two
    /// thirds of a season, so a flower photographed at the start of a season
    /// is still worth working at the end of it. Together with `patchFadeDays`
    /// a patch is finished after about half a simulated year, which at the
    /// shipped clock is a fortnight of real time — often enough to be a habit,
    /// rarely enough not to be a chore.
    public var patchFreshDays: Int = 60

    /// Days a patch takes to decline from full to nothing once it starts.
    public var patchFadeDays: Int = 120

    // MARK: - Swarming

    /// How far into spring a colony must be before it will swarm, and how far
    /// into summer it will still do so. Both are fractions of their season.
    ///
    /// Swarming is the product of the spring build-up rather than its opening
    /// move, and the window is narrow in reality: late April to early June in
    /// Britain. Sweepable because the two ends trade directly against each
    /// other — too early and colonies halve themselves coming out of winter,
    /// too late and they stop dividing at all.
    /// How many times the working reserve a colony must be holding before it
    /// will swarm, as a multiple of `layingReservePerBee` across the colony.
    ///
    /// Swarming bees gorge before they leave. A colony that cannot provision
    /// both halves stays put, which is what stops a division on thin stores in
    /// late spring — the pattern that used to dominate second-year deaths.
    public var swarmProvisionMultiple: Double = 3.0

    public var swarmSeasonStart: Double = Season.swarmSeasonStartsAtSpringProgress
    public var swarmSeasonEnd: Double = Season.swarmSeasonEndsAtSummerProgress

    public var swarmCongestionThreshold: Double = 0.45
    public var swarmMinimumPopulation: Int = 90
    public var swarmCellChance: Double = 0.45
    /// Days a swarm cell must have developed before the colony departs.
    public var swarmDepartureDay: Int = 8
    public var swarmDepartureShare: Double = 0.6
    public var honeyCarriedPerSwarmBee: Double = 0.12

    // MARK: - The answers to congestion

    /// How much room one `addComb` gives, as a fraction of the site's natural
    /// cavity.
    ///
    /// A quarter, so the decision is worth taking more than once and no single
    /// answer removes swarming from the game. What it buys is space, not comb:
    /// `ConstructionSystem` still has to draw into it, during a flow, at seven
    /// honey to one of wax.
    public var combExtensionStep: Double = 0.25

    /// The share of adults that goes with a deliberate split.
    ///
    /// Half what a swarm takes, and taken from the other end of the age range.
    /// A swarm is the flying bees leaving of their own accord; a division the
    /// player makes moves the queen and the house bees, and the foragers —
    /// who know where the nest is — stay with it. That difference is the whole
    /// reason to split rather than let them go.
    public var splitDepartureShare: Double = 0.3

    /// How far a queen cell must have developed before the colony can be
    /// divided on purpose.
    ///
    /// A beekeeper performs an artificial swarm on a *charged* cell, not on a
    /// cup with an egg in it, and the reason is arithmetic. The colony that
    /// stays is queenless from the moment the queen leaves until the kept cell
    /// emerges. A swarm goes at `swarmDepartureDay`, four days short of
    /// emergence; a split taken the day cells were started leaves the colony
    /// without a laying queen for the whole twelve, through the best of the
    /// build-up.
    ///
    /// That was measured before it was fixed: splitting on sight took two-year
    /// survival to 30% against instinct's 66%, and the difference was almost
    /// entirely those extra queenless days.
    public var splitEarliestCellDay: Int = 6

    /// How many queen cells a deliberate split leaves the parent colony.
    /// Zero means all of them.
    ///
    /// A beekeeper knocks the rest down to stop an afterswarm following the
    /// artificial swarm out, and that is why this started at one. It is now
    /// redundant: afterswarms are prevented properly, because a mated queen
    /// retires the leftover cells and a colony headed by a drone layer cannot
    /// swarm at all.
    ///
    /// What tearing them down does still do is throw away the insurance
    /// `emergeQueens` deliberately keeps — developing cells are left standing
    /// against the new virgin failing her mating flight — so a split that kept
    /// one had staked the colony on a single queen getting back.
    public var splitQueenCellsKept: Int = 0

    // MARK: - Absconding

    /// Unrepelled attacks within three weeks before the colony considers
    /// abandoning the nest.
    public var abscondAttackThreshold: Int = 6
    /// Comb below which the nest counts as ruined.
    public var abscondCombThreshold: Int = 25
    /// Hard ceiling on the daily chance of walking out.
    public var abscondMaximumChance: Double = 0.03

    // MARK: - Pheromones

    /// Total queen signal available for distribution.
    public var queenPheromoneOutput: Double = 1.6
    /// Colony size at which the queen's signal is halved by dilution.
    ///
    /// This is what actually sets the swarming threshold: queen rearing starts
    /// once the perceived signal drops below `Pheromones.queenRearingThreshold`,
    /// and the signal thins as the colony grows. At 220 that point sat around
    /// 565 bees — larger than most colonies ever reach, so no colony ever
    /// swarmed. Real colonies swarm most years.
    ///
    /// 130 was still too high: it put the queen's signal below the
    /// queen-rearing threshold only past ~276 adults, and colonies peak near
    /// 155, so swarming stayed arithmetically unreachable and 24 test colonies
    /// recorded 0.00 swarms over 400 days. At 45 the signal weakens from about
    /// 96 adults, which lines up with `swarmMinimumPopulation` — strong
    /// colonies divide, weak ones do not. Measured: 1.04 swarms per colony-year
    /// over 120 trials.
    public var pheromoneDilutionScale: Double = 45
    public var broodPheromoneScale: Double = 260
    /// How quickly perceived concentration tracks its target.
    public var pheromoneResponseRate: Double = 0.05
    public var alarmDecayPerTick: Double = 0.86

    // MARK: - What alarm pheromone actually does
    //
    // It was tracked, raised on every attack and decayed on a careful
    // schedule, and read by nothing. These three constants are what it now
    // drives, and they are deliberately sized *below* the equivalent
    // `HivePosture` multipliers.
    //
    // That relationship is the design, not an accident of tuning. Alarm is the
    // colony's own instinctive version of holding the entrance: it costs
    // foraging, it kills defenders, and it helps. A posture the player chooses
    // has to be worth choosing, so it has to beat what the bees do on their
    // own — and instinct has to be a real answer rather than an absence, or
    // the player who never opens the app is being punished for it.

    /// How much better an alarmed colony defends. At full alarm this is a
    /// ×1.35, against ×1.6 for holding the entrance and ×1.4 for narrowing it.
    ///
    /// Isopentyl acetate from a stinging guard recruits other bees to the
    /// spot, which is a real and much-measured effect: it is why one sting
    /// draws more.
    public var alarmDefenceBoost: Double = 0.35

    /// What it costs in foraging. At full alarm a ×0.90, against ×0.8 for
    /// narrowing the entrance and ×0.7 for holding it.
    ///
    /// An alarmed colony has bees at the entrance and in the air around it
    /// rather than in the field, and it stays that way for a few hours — but
    /// it does not stop flying, which is the difference between being alarmed
    /// and being told to stay in.
    ///
    /// This was 0.20 first, which is exactly what narrowing the entrance
    /// costs, and it broke the rule above: instinct came out as good as a
    /// posture the player had to choose. It also cost more than the defence
    /// boost gave back — 5% of a colony's whole two-year intake and four
    /// points of survival, because a multi-day siege raises alarm again every
    /// day and holds it up. At 0.10 the package changes what it should and
    /// nothing else: repel rate 44.9% to 46.2%, nectar down 2.0%, survival
    /// unmoved at 66%.
    public var alarmForageCost: Double = 0.10

    /// And what it costs in bees. At full alarm a ×1.25 on defender
    /// casualties, against ×1.3 for holding the entrance.
    ///
    /// A bee that stings a mammal dies doing it, so a colony that stings more
    /// readily loses more. This is what stops alarm being free.
    public var alarmCasualtyRate: Double = 0.25
    public var nasonovDecayPerTick: Double = 0.9

    // MARK: - Propolis

    public var targetPropolisEnvelope: Double = 0.8
    public var propolisPerUnit: Double = 0.05
    public var propolisDecayPerDay: Double = 0.004

    // MARK: - Disease

    public var pathogenSeedLevel: Double = 0.02

    /// Baseline daily fraction of an infection the colony shakes off through
    /// ordinary grooming, cleaning and turnover of infected bees.
    public var pathogenBaseRecovery: Double = 0.02
    /// Extra daily nosema clearance on a day the bees can fly out and cleanse.
    public var nosemaCleansingRecovery: Double = 0.06
    public var hygienicRemovalRate: Double = 0.16
    public var viralBroodDamage: Double = 0.05
    public var criticalInfectionLevel: Double = 0.65

    /// Scales how often pathogens find the colony at all. The difficulty
    /// presets move this rather than editing the per-pathogen table.
    public var pathogenArrivalMultiplier: Double = 1.0

    /// Daily arrival chance per pathogen, before exposure scaling.
    public func pathogenArrivalChance(for pathogen: Pathogen) -> Double {
        baseArrivalChance(for: pathogen) * pathogenArrivalMultiplier
    }

    private func baseArrivalChance(for pathogen: Pathogen) -> Double {
        switch pathogen {
        case .varroa: return 0.0040
        case .nosema: return 0.0022
        case .chalkbrood: return 0.0016
        case .americanFoulbrood: return 0.0004
        // Never arrives on its own; it is seeded by its varroa vector.
        case .deformedWingVirus: return 0
        }
    }

    // MARK: - Defence

    public var guardStrength: Double = 0.09
    public var predatorStrength: Double = 1.0

    // MARK: - Colony viability

    public var minimumViablePopulation: Int = 6

    public init() {}
}

// MARK: - Presets

extension SimulationConfig {

    /// The tuned default.
    public static let standard = SimulationConfig()

    /// Forgiving: for onboarding, and for players who want a pet rather than a
    /// challenge.
    ///
    /// Note the swarm and mating adjustments. Simply handing a colony more
    /// forage makes the game *harder*, not easier â€” a well-fed colony builds up
    /// faster, crowds its nest sooner and swarms far more often, and each swarm
    /// costs it sixty per cent of its workforce and stakes its future on a
    /// virgin queen surviving a mating flight. Measured across thirty colonies,
    /// richer forage alone dropped survival from 70% to 40%. A gentler game has
    /// to damp the swarming too.
    public static var gentle: SimulationConfig {
        var config = SimulationConfig()

        // More coming in, and less going out.
        config.nectarPerForager *= 1.6
        config.pollenPerForager *= 1.4
        config.patchDailyRegrowth *= 1.5
        config.forageWearPerTick *= 0.7
        config.honeyPerAdult *= 0.8
        config.winterProvisioningMargin = 1.15

        // Less going wrong.
        config.honeyPerDegreeHeating *= 0.6
        config.broodLossPerDegree *= 0.5
        config.broodStarvationRate *= 0.5
        config.hygienicRemovalRate *= 1.6
        config.guardStrength *= 1.5

        // And a colony that stays together.
        config.swarmCellChance *= 0.35
        config.swarmCongestionThreshold += 0.08
        config.matingFlightPredationChance *= 0.5
        config.supersedureChance *= 0.6

        // Fewer things coming for it.
        config.predatorStrength *= 0.55
        config.pathogenArrivalMultiplier = 0.5
        config.adultStarvationRate *= 0.5
        config.abscondMaximumChance *= 0.4

        return config
    }

    /// Unforgiving, and closer to what a real colony faces.
    public static var harsh: SimulationConfig {
        var config = SimulationConfig()
        config.nectarPerForager *= 0.72
        config.honeyPerAdult *= 1.15
        config.patchDailyRegrowth *= 0.7
        config.honeyPerDegreeHeating *= 1.4
        config.hygienicRemovalRate *= 0.7
        config.guardStrength *= 0.7
        config.matingFlightPredationChance *= 1.6
        config.predatorStrength *= 1.3
        config.pathogenArrivalMultiplier = 1.8
        config.swarmCellChance *= 1.3
        // Set explicitly rather than inherited. The standard margin dropped
        // from 1.3 to 1.0 when swarming and varroa started actually happening,
        // and harsh — which already cuts forage by nearly a third — collapsed
        // to 7% survival on the inherited value.
        config.winterProvisioningMargin = 1.3
        return config
    }
}

// MARK: - Reading a save

extension SimulationConfig {

    /// Decoded by hand, one key at a time, so that a key added since a save
    /// was written takes today's default rather than making the save
    /// unreadable.
    ///
    /// The whole config is written into every save file, and a synthesised
    /// decoder throws on the first key it cannot find. `GameStore.load` used
    /// to treat an unreadable save as no save at all, so every balance number
    /// added here — `wildPatchDensity` and the rest of the country on
    /// 2026-09-16, and every one after — would have made the colony of
    /// anybody who updated unreadable. This is the rule `World.init(from:)`
    /// states, applied to the type most likely to break it.
    ///
    /// A missing key takes the *standard* value, not the value of whatever
    /// preset the colony was started on. A preset only adjusts numbers that
    /// already existed when it was chosen, so a key the save has never heard
    /// of is one no preset had an opinion about when the player picked it.
    ///
    /// Only `init(from:)` is written out; the encoder is still synthesised,
    /// so the file's shape is exactly what it was. **A new property needs a
    /// line here.** Without one it still decodes, to its default, whatever the
    /// save said — which is why `SaveCompatibilityTests` moves every property
    /// off its default and fails on any that does not come back.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SimulationConfig()

        func read<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) throws -> Value {
            try container.decodeIfPresent(Value.self, forKey: key) ?? fallback
        }

        // Foraging
        nectarPerForager = try read(.nectarPerForager, defaults.nectarPerForager)
        pollenPerForager = try read(.pollenPerForager, defaults.pollenPerForager)
        waterPerCarrier = try read(.waterPerCarrier, defaults.waterPerCarrier)
        propolisChance = try read(.propolisChance, defaults.propolisChance)
        flightEnergyPerForager = try read(.flightEnergyPerForager, defaults.flightEnergyPerForager)
        forageWearPerTick = try read(.forageWearPerTick, defaults.forageWearPerTick)
        danceRecruitmentExponent = try read(
            .danceRecruitmentExponent, defaults.danceRecruitmentExponent
        )
        patchDailyRegrowth = try read(.patchDailyRegrowth, defaults.patchDailyRegrowth)
        winterForageOverride = try container.decodeIfPresent(
            Double.self, forKey: .winterForageOverride
        )
        pollenReserveDays = try read(.pollenReserveDays, defaults.pollenReserveDays)
        minimumPollenReserve = try read(.minimumPollenReserve, defaults.minimumPollenReserve)

        // In-hive processing
        nectarPerHoney = try read(.nectarPerHoney, defaults.nectarPerHoney)
        honeyPerConcentrator = try read(.honeyPerConcentrator, defaults.honeyPerConcentrator)
        beeBreadPerPacker = try read(.beeBreadPerPacker, defaults.beeBreadPerPacker)
        honeyPerBeeBread = try read(.honeyPerBeeBread, defaults.honeyPerBeeBread)
        pollenPerBeeBread = try read(.pollenPerBeeBread, defaults.pollenPerBeeBread)
        royalJellyPerNurse = try read(.royalJellyPerNurse, defaults.royalJellyPerNurse)
        honeyPerRoyalJelly = try read(.honeyPerRoyalJelly, defaults.honeyPerRoyalJelly)
        pollenPerRoyalJelly = try read(.pollenPerRoyalJelly, defaults.pollenPerRoyalJelly)
        foodBufferDays = try read(.foodBufferDays, defaults.foodBufferDays)

        // Wax and comb
        honeyPerWax = try read(.honeyPerWax, defaults.honeyPerWax)
        waxPerBuilder = try read(.waxPerBuilder, defaults.waxPerBuilder)
        cellsPerBuilderPerTick = try read(.cellsPerBuilderPerTick, defaults.cellsPerBuilderPerTick)
        buildCongestionThreshold = try read(
            .buildCongestionThreshold, defaults.buildCongestionThreshold
        )
        buildHoneyReserve = try read(.buildHoneyReserve, defaults.buildHoneyReserve)
        waxIncomeShare = try read(.waxIncomeShare, defaults.waxIncomeShare)
        minimumWaxTemperature = try read(.minimumWaxTemperature, defaults.minimumWaxTemperature)
        cellsMaintainedPerBee = try read(.cellsMaintainedPerBee, defaults.cellsMaintainedPerBee)
        combDecayRate = try read(.combDecayRate, defaults.combDecayRate)

        // Consumption
        honeyPerAdult = try read(.honeyPerAdult, defaults.honeyPerAdult)
        foodPerLarva = try read(.foodPerLarva, defaults.foodPerLarva)
        royalJellyDays = try read(.royalJellyDays, defaults.royalJellyDays)
        queenRoyalJellyPerDay = try read(.queenRoyalJellyPerDay, defaults.queenRoyalJellyPerDay)
        queenCellRoyalJellyPerDay = try read(
            .queenCellRoyalJellyPerDay, defaults.queenCellRoyalJellyPerDay
        )
        queenJellyReserveDays = try read(.queenJellyReserveDays, defaults.queenJellyReserveDays)
        queenCellAbandonChancePerTick = try read(
            .queenCellAbandonChancePerTick, defaults.queenCellAbandonChancePerTick
        )
        starvationDamagePerTick = try read(
            .starvationDamagePerTick, defaults.starvationDamagePerTick
        )
        malnutritionDamagePerTick = try read(
            .malnutritionDamagePerTick, defaults.malnutritionDamagePerTick
        )
        broodRecoveryPerTick = try read(.broodRecoveryPerTick, defaults.broodRecoveryPerTick)
        queenStarvationDamagePerTick = try read(
            .queenStarvationDamagePerTick, defaults.queenStarvationDamagePerTick
        )
        queenRecoveryPerTick = try read(.queenRecoveryPerTick, defaults.queenRecoveryPerTick)
        broodStarvationRate = try read(.broodStarvationRate, defaults.broodStarvationRate)
        adultStarvationRate = try read(.adultStarvationRate, defaults.adultStarvationRate)

        // Thermoregulation
        targetTemperature = try read(.targetTemperature, defaults.targetTemperature)
        broodlessClusterTemperature = try read(
            .broodlessClusterTemperature, defaults.broodlessClusterTemperature
        )
        minimumBroodTemperature = try read(
            .minimumBroodTemperature, defaults.minimumBroodTemperature
        )
        safeTemperatureBand = try read(.safeTemperatureBand, defaults.safeTemperatureBand)
        targetHumidity = try read(.targetHumidity, defaults.targetHumidity)
        thermalLeakRate = try read(.thermalLeakRate, defaults.thermalLeakRate)
        heatingPerAdult = try read(.heatingPerAdult, defaults.heatingPerAdult)
        honeyPerDegreeHeating = try read(.honeyPerDegreeHeating, defaults.honeyPerDegreeHeating)
        coolingPerFanner = try read(.coolingPerFanner, defaults.coolingPerFanner)
        waterPerDegreeCooling = try read(.waterPerDegreeCooling, defaults.waterPerDegreeCooling)
        broodLossPerDegree = try read(.broodLossPerDegree, defaults.broodLossPerDegree)
        broodDamagePerDegree = try read(.broodDamagePerDegree, defaults.broodDamagePerDegree)

        // Queen and brood
        maxEggsPerDay = try read(.maxEggsPerDay, defaults.maxEggsPerDay)
        nursesPerEgg = try read(.nursesPerEgg, defaults.nursesPerEgg)
        droneEggShare = try read(.droneEggShare, defaults.droneEggShare)
        droneRearingMinimumPopulation = try read(
            .droneRearingMinimumPopulation, defaults.droneRearingMinimumPopulation
        )
        droneEvictionChance = try read(.droneEvictionChance, defaults.droneEvictionChance)
        layingEnergyThreshold = try read(.layingEnergyThreshold, defaults.layingEnergyThreshold)
        layingReservePerBee = try read(.layingReservePerBee, defaults.layingReservePerBee)
        broodReserveDrawRate = try read(.broodReserveDrawRate, defaults.broodReserveDrawRate)
        broodFoodOverhead = try read(.broodFoodOverhead, defaults.broodFoodOverhead)
        autumnIncomeOptimism = try read(.autumnIncomeOptimism, defaults.autumnIncomeOptimism)
        winterProvisioningMargin = try read(
            .winterProvisioningMargin, defaults.winterProvisioningMargin
        )
        winterBuildUpStart = try read(.winterBuildUpStart, defaults.winterBuildUpStart)
        broodPerNurse = try read(.broodPerNurse, defaults.broodPerNurse)
        queenFailureVitality = try read(.queenFailureVitality, defaults.queenFailureVitality)
        queenSupersedureAge = try read(.queenSupersedureAge, defaults.queenSupersedureAge)
        supersedureChance = try read(.supersedureChance, defaults.supersedureChance)
        maximumQueenCells = try read(.maximumQueenCells, defaults.maximumQueenCells)
        emergencyQueenCellBurst = try read(
            .emergencyQueenCellBurst, defaults.emergencyQueenCellBurst
        )
        matingFlightEarliestDay = try read(
            .matingFlightEarliestDay, defaults.matingFlightEarliestDay
        )
        matingFlightLatestDay = try read(.matingFlightLatestDay, defaults.matingFlightLatestDay)
        matingFlightMinimumTemperature = try read(
            .matingFlightMinimumTemperature, defaults.matingFlightMinimumTemperature
        )
        matingFlightPredationChance = try read(
            .matingFlightPredationChance, defaults.matingFlightPredationChance
        )
        baseDroneEncounters = try read(.baseDroneEncounters, defaults.baseDroneEncounters)
        layingWorkerOnsetDays = try read(.layingWorkerOnsetDays, defaults.layingWorkerOnsetDays)
        layingWorkerEggsPerDay = try read(.layingWorkerEggsPerDay, defaults.layingWorkerEggsPerDay)
        flowThresholdPerBee = try read(.flowThresholdPerBee, defaults.flowThresholdPerBee)
        dearthThresholdPerBee = try read(.dearthThresholdPerBee, defaults.dearthThresholdPerBee)

        // Decisions
        entranceSealPropolis = try read(.entranceSealPropolis, defaults.entranceSealPropolis)
        sealedEntranceMouseFactor = try read(
            .sealedEntranceMouseFactor, defaults.sealedEntranceMouseFactor
        )
        sealedEntranceDiseaseFactor = try read(
            .sealedEntranceDiseaseFactor, defaults.sealedEntranceDiseaseFactor
        )
        sealedEntranceHeatRetention = try read(
            .sealedEntranceHeatRetention, defaults.sealedEntranceHeatRetention
        )
        swarmDiscouragementEffect = try read(
            .swarmDiscouragementEffect, defaults.swarmDiscouragementEffect
        )
        sharedPatchYield = try read(.sharedPatchYield, defaults.sharedPatchYield)

        // The country
        wildPatchYield = try read(.wildPatchYield, defaults.wildPatchYield)
        danceDistanceExponent = try read(.danceDistanceExponent, defaults.danceDistanceExponent)
        danceFloorPatches = try read(.danceFloorPatches, defaults.danceFloorPatches)
        wildPatchDensity = try read(.wildPatchDensity, defaults.wildPatchDensity)
        biomeThreatScale = try read(.biomeThreatScale, defaults.biomeThreatScale)
        scoutShare = try read(.scoutShare, defaults.scoutShare)
        scoutDays = try read(.scoutDays, defaults.scoutDays)
        explorationShare = try read(.explorationShare, defaults.explorationShare)
        explorationChance = try read(.explorationChance, defaults.explorationChance)
        patchFreshDays = try read(.patchFreshDays, defaults.patchFreshDays)
        patchFadeDays = try read(.patchFadeDays, defaults.patchFadeDays)

        // Swarming
        swarmProvisionMultiple = try read(.swarmProvisionMultiple, defaults.swarmProvisionMultiple)
        swarmSeasonStart = try read(.swarmSeasonStart, defaults.swarmSeasonStart)
        swarmSeasonEnd = try read(.swarmSeasonEnd, defaults.swarmSeasonEnd)
        swarmCongestionThreshold = try read(
            .swarmCongestionThreshold, defaults.swarmCongestionThreshold
        )
        swarmMinimumPopulation = try read(.swarmMinimumPopulation, defaults.swarmMinimumPopulation)
        swarmCellChance = try read(.swarmCellChance, defaults.swarmCellChance)
        swarmDepartureDay = try read(.swarmDepartureDay, defaults.swarmDepartureDay)
        swarmDepartureShare = try read(.swarmDepartureShare, defaults.swarmDepartureShare)
        honeyCarriedPerSwarmBee = try read(
            .honeyCarriedPerSwarmBee, defaults.honeyCarriedPerSwarmBee
        )

        // The answers to congestion
        combExtensionStep = try read(.combExtensionStep, defaults.combExtensionStep)
        splitDepartureShare = try read(.splitDepartureShare, defaults.splitDepartureShare)
        splitEarliestCellDay = try read(.splitEarliestCellDay, defaults.splitEarliestCellDay)
        splitQueenCellsKept = try read(.splitQueenCellsKept, defaults.splitQueenCellsKept)

        // Absconding
        abscondAttackThreshold = try read(.abscondAttackThreshold, defaults.abscondAttackThreshold)
        abscondCombThreshold = try read(.abscondCombThreshold, defaults.abscondCombThreshold)
        abscondMaximumChance = try read(.abscondMaximumChance, defaults.abscondMaximumChance)

        // Pheromones
        queenPheromoneOutput = try read(.queenPheromoneOutput, defaults.queenPheromoneOutput)
        pheromoneDilutionScale = try read(.pheromoneDilutionScale, defaults.pheromoneDilutionScale)
        broodPheromoneScale = try read(.broodPheromoneScale, defaults.broodPheromoneScale)
        pheromoneResponseRate = try read(.pheromoneResponseRate, defaults.pheromoneResponseRate)
        alarmDecayPerTick = try read(.alarmDecayPerTick, defaults.alarmDecayPerTick)

        // What alarm pheromone actually does
        alarmDefenceBoost = try read(.alarmDefenceBoost, defaults.alarmDefenceBoost)
        alarmForageCost = try read(.alarmForageCost, defaults.alarmForageCost)
        alarmCasualtyRate = try read(.alarmCasualtyRate, defaults.alarmCasualtyRate)
        nasonovDecayPerTick = try read(.nasonovDecayPerTick, defaults.nasonovDecayPerTick)

        // Propolis
        targetPropolisEnvelope = try read(.targetPropolisEnvelope, defaults.targetPropolisEnvelope)
        propolisPerUnit = try read(.propolisPerUnit, defaults.propolisPerUnit)
        propolisDecayPerDay = try read(.propolisDecayPerDay, defaults.propolisDecayPerDay)

        // Disease
        pathogenSeedLevel = try read(.pathogenSeedLevel, defaults.pathogenSeedLevel)
        pathogenBaseRecovery = try read(.pathogenBaseRecovery, defaults.pathogenBaseRecovery)
        nosemaCleansingRecovery = try read(
            .nosemaCleansingRecovery, defaults.nosemaCleansingRecovery
        )
        hygienicRemovalRate = try read(.hygienicRemovalRate, defaults.hygienicRemovalRate)
        viralBroodDamage = try read(.viralBroodDamage, defaults.viralBroodDamage)
        criticalInfectionLevel = try read(.criticalInfectionLevel, defaults.criticalInfectionLevel)
        pathogenArrivalMultiplier = try read(
            .pathogenArrivalMultiplier, defaults.pathogenArrivalMultiplier
        )

        // Defence
        guardStrength = try read(.guardStrength, defaults.guardStrength)
        predatorStrength = try read(.predatorStrength, defaults.predatorStrength)

        // Colony viability
        minimumViablePopulation = try read(
            .minimumViablePopulation, defaults.minimumViablePopulation
        )
    }
}
