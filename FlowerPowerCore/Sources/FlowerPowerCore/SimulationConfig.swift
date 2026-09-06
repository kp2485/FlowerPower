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
    /// The real difference between a shared flower and one you found is not
    /// yield but *distance*, and the engine already handles that: a share
    /// carrying a coordinate is placed relative to the recipient's own hive,
    /// and may be out of foraging range entirely.
    public var sharedPatchYield: Double = 1.0

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







