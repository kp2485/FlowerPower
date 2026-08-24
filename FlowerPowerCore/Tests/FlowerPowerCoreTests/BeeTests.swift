import XCTest
@testable import FlowerPowerCore

final class WorkerJobTests: XCTestCase {

    /// Regression test for the original model, where jobs were assigned in a
    /// `switch` over overlapping age ranges. First-match-wins meant `12..<35`
    /// swallowed ages 12-34, so guard bees and — critically — forager bees
    /// could never exist, and no nectar could ever enter the hive.
    func testGuardAndForagerJobsAreReachable() {
        let guards = (0..<60).filter { WorkerJob.jobs(forAdultAge: $0).contains(.guardBee) }
        let foragers = (0..<60).filter { WorkerJob.jobs(forAdultAge: $0).contains(.foragingBee) }

        XCTAssertEqual(guards, Array(18..<21))

        // Foraging runs from 22 and never stops: ages past the end of the table
        // clamp to it, so an old bee carries on foraging until she dies rather
        // than ageing out of having any job at all.
        XCTAssertEqual(foragers.first, 22)
        XCTAssertEqual(foragers.last, 59)
        XCTAssertTrue(foragers.contains(50))
    }

    /// Nobody ages out of work. Winter bees live months and would otherwise run
    /// off the end of the age table entirely.
    func testOldBeesKeepForaging() {
        XCTAssertTrue(WorkerJob.jobs(forAdultAge: 200).contains(.foragingBee))
        XCTAssertFalse(WorkerJob.jobs(forAdultAge: 200).isEmpty)
    }

    func testEveryJobIsReachable() {
        for job in WorkerJob.allCases {
            let ages = (0..<60).filter { WorkerJob.jobs(forAdultAge: $0).contains(job) }
            XCTAssertFalse(ages.isEmpty, "\(job) is unreachable at every age")
        }
    }

    /// The old `switch` guaranteed at most one range matched, which defeated
    /// the point of modelling jobs as a Set.
    func testWorkersHoldSeveralJobsAtOnce() {
        let jobs = WorkerJob.jobs(forAdultAge: 12)
        XCTAssertTrue(jobs.contains(.mortuary))
        XCTAssertTrue(jobs.contains(.droneFeeder))
        XCTAssertTrue(jobs.contains(.nectarConcentrator))
        XCTAssertTrue(jobs.contains(.honeycombBuilder))
        XCTAssertGreaterThan(jobs.count, 3)
    }

    /// Ages 35-41 previously fell through to `default` and produced no jobs at
    /// all, silently idling bees that should have been foraging.
    func testNoWorkingAgeIsJobless() {
        for age in 0..<42 {
            XCTAssertFalse(
                WorkerJob.jobs(forAdultAge: age).isEmpty,
                "a \(age)-day-old worker has no job"
            )
        }
    }

    func testBroodHasNoJobs() {
        for stage in [DevelopmentStage.egg, .larva, .pupa] {
            let bee = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: stage, daysInStage: 5)
            XCTAssertTrue(bee.jobs.isEmpty, "a \(stage) was assigned jobs")
        }
    }

    func testNonWorkersHaveNoJobs() {
        XCTAssertTrue(
            Bee(id: EntityID(rawValue: 1), kind: .queen, stage: .adult, daysInStage: 5).jobs.isEmpty
        )
        XCTAssertTrue(
            Bee(id: EntityID(rawValue: 2), kind: .drone, stage: .adult, daysInStage: 5).jobs.isEmpty
        )
    }

    // MARK: - Player assignment

    func testPlayerAssignmentOverridesNaturalJobs() {
        var bee = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 12)
        XCTAssertGreaterThan(bee.jobs.count, 1)

        bee.assignedJob = .fanning
        XCTAssertEqual(bee.jobs, [.fanning])
    }

    /// A bee cannot be assigned work she is physically incapable of.
    func testAssignmentCannotExceedCapability() {
        var bee = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 2)
        bee.assignedJob = .foragingBee     // far too young

        XCTAssertFalse(bee.performs(.foragingBee))
        XCTAssertTrue(bee.performs(.nurseBee), "she should fall back to age-appropriate work")
    }

    /// A bee too damaged to fly cannot be sent to the field — but she is not
    /// left idle either. She gets on with whatever inside work she can do.
    func testFlightlessBeeCannotBeAssignedFieldWork() {
        var bee = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 25)
        bee.damage(0.9)
        bee.assignedJob = .foragingBee

        XCTAssertFalse(bee.canFly)
        XCTAssertFalse(bee.performs(.foragingBee), "a flightless bee is still being sent out")
        XCTAssertFalse(bee.jobs.isEmpty, "she should fall back to inside work, not stand about")
        XCTAssertTrue(bee.jobs.allSatisfy { !$0.requiresFlight })
    }
}

final class BeeDevelopmentTests: XCTestCase {

    /// Features.md tabulates the third column as total days to emergence, which
    /// should land close to the real figures: queen 16, worker 21, drone 24.
    func testTotalDevelopmentMatchesBiology() {
        XCTAssertEqual(BeeDevelopment.totalDaysToEmergence(for: .queen), 15)
        XCTAssertEqual(BeeDevelopment.totalDaysToEmergence(for: .worker), 20)
        XCTAssertEqual(BeeDevelopment.totalDaysToEmergence(for: .drone), 23)
    }

    func testUpgradesShortenDevelopment() {
        for kind in BeeKind.allCases {
            let base = BeeDevelopment.totalDaysToEmergence(for: kind, upgrade: .none)
            let first = BeeDevelopment.totalDaysToEmergence(for: kind, upgrade: .first)
            let second = BeeDevelopment.totalDaysToEmergence(for: kind, upgrade: .second)
            XCTAssertLessThan(first, base)
            XCTAssertLessThan(second, first)
        }
    }

    func testEveryStageLastsAtLeastOneDay() {
        for kind in BeeKind.allCases {
            for upgrade in BroodUpgrade.allCases {
                for stage in [DevelopmentStage.egg, .larva, .pupa] {
                    XCTAssertGreaterThan(
                        BeeDevelopment.days(for: kind, stage: stage, upgrade: upgrade), 0,
                        "\(kind)/\(stage)/\(upgrade) has a non-positive duration"
                    )
                }
            }
        }
    }

    func testBeeProgressesEggToAdult() {
        var bee = Bee(id: EntityID(rawValue: 1), kind: .worker)
        var emergedOn: Int?

        for day in 1...40 {
            if case .advancedTo(.adult) = bee.advanceOneDay(upgrade: .none, day: 100) {
                emergedOn = day
                break
            }
        }

        XCTAssertEqual(emergedOn, 20)
        XCTAssertTrue(bee.isAdult)
        XCTAssertEqual(bee.daysInStage, 0, "adult age must restart at emergence")
    }

    func testOnlyPupaeAreCapped() {
        XCTAssertTrue(DevelopmentStage.pupa.isCapped)
        XCTAssertFalse(DevelopmentStage.larva.isCapped)
        XCTAssertFalse(DevelopmentStage.egg.isCapped)
    }

    // MARK: - Lifespan

    func testAdultDiesOfOldAge() {
        var bee = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 41)
        XCTAssertEqual(bee.advanceOneDay(upgrade: .none, day: 100), .diedOfOldAge)
    }

    /// Winter bees are a different animal: reared in autumn, fat-bodied, and
    /// alive for six months rather than six weeks. They are what carries a
    /// colony to spring.
    func testWinterBeesLiveFarLonger() {
        var winterBee = Bee(
            id: EntityID(rawValue: 1), kind: .worker,
            stage: .adult, daysInStage: 41, physiology: .winter
        )
        XCTAssertEqual(winterBee.advanceOneDay(upgrade: .none, day: 300), .aged)
        XCTAssertGreaterThan(winterBee.effectiveLifespanDays, 100)

        var summerBee = Bee(
            id: EntityID(rawValue: 2), kind: .worker,
            stage: .adult, daysInStage: 41, physiology: .summer
        )
        XCTAssertEqual(summerBee.advanceOneDay(upgrade: .none, day: 300), .diedOfOldAge)
    }

    /// Physiology is fixed at emergence by when the bee emerges, not when she
    /// was laid or what season she later lives through.
    ///
    /// The switchover is in *late summer*, not at the autumn boundary: brood
    /// laid in August emerges in September and forms the winter cluster.
    func testPhysiologyIsSetAtEmergence() {
        func emerge(onDay day: Int) -> WorkerPhysiology {
            var bee = Bee(id: EntityID(rawValue: 1), kind: .worker)
            for _ in 0..<40 {
                if case .advancedTo(.adult) = bee.advanceOneDay(upgrade: .none, day: day) {
                    break
                }
            }
            return bee.physiology
        }

        XCTAssertEqual(emerge(onDay: 20), .summer, "spring")
        XCTAssertEqual(emerge(onDay: 100), .summer, "early summer")
        XCTAssertEqual(emerge(onDay: 150), .winter, "late summer rears winter bees")
        XCTAssertEqual(emerge(onDay: 200), .winter, "autumn")
        XCTAssertEqual(emerge(onDay: 300), .winter, "winter")
    }

    func testWinterRearingBeginsInLateSummer() {
        XCTAssertFalse(Season.isRearingWinterBees(on: 100))
        XCTAssertTrue(Season.isRearingWinterBees(on: 150))
        XCTAssertTrue(Season.isRearingWinterBees(on: 200))
        XCTAssertFalse(Season.isRearingWinterBees(on: 10))
    }

    func testWinterBeesWearMoreSlowly() {
        var summerBee = Bee(
            id: EntityID(rawValue: 1), kind: .worker,
            stage: .adult, daysInStage: 25, physiology: .summer
        )
        var winterBee = Bee(
            id: EntityID(rawValue: 2), kind: .worker,
            stage: .adult, daysInStage: 25, physiology: .winter
        )
        summerBee.accumulateWear(10)
        winterBee.accumulateWear(10)

        XCTAssertGreaterThan(summerBee.wear, winterBee.wear)
    }

    /// Worker lifespan is governed by flying, not by the calendar. A bee that
    /// has foraged hard dies sooner than one of the same age that has not.
    func testWearShortensLife() {
        var worn = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 30)
        worn.accumulateWear(15)

        var fresh = Bee(id: EntityID(rawValue: 2), kind: .worker, stage: .adult, daysInStage: 30)

        XCTAssertEqual(worn.advanceOneDay(upgrade: .none, day: 100), .diedOfOldAge)
        XCTAssertEqual(fresh.advanceOneDay(upgrade: .none, day: 100), .aged)
    }

    func testPoorConditionShortensLife() {
        var damaged = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 26)
        damaged.damage(0.9)

        var healthy = Bee(id: EntityID(rawValue: 2), kind: .worker, stage: .adult, daysInStage: 26)

        XCTAssertEqual(damaged.advanceOneDay(upgrade: .none, day: 100), .diedOfOldAge)
        XCTAssertEqual(healthy.advanceOneDay(upgrade: .none, day: 100), .aged)
    }

    func testVitalityIsClamped() {
        var bee = Bee(id: EntityID(rawValue: 1), kind: .worker)
        bee.damage(5)
        XCTAssertEqual(bee.vitality, 0)
        bee.recover(5)
        XCTAssertEqual(bee.vitality, 1)
    }

    func testEffectivenessTracksVitality() {
        var strong = Bee(id: EntityID(rawValue: 1), kind: .worker, stage: .adult, daysInStage: 10)
        var weak = Bee(id: EntityID(rawValue: 2), kind: .worker, stage: .adult, daysInStage: 10)
        weak.damage(0.5)
        strong.recover(0)

        XCTAssertGreaterThan(strong.effectiveness, weak.effectiveness)
        XCTAssertGreaterThan(weak.effectiveness, 0, "a damaged bee still contributes something")
    }
}

final class SeasonAndWeatherTests: XCTestCase {

    func testSeasonsCycle() {
        XCTAssertEqual(Season(day: 0), .spring)
        XCTAssertEqual(Season(day: 90), .summer)
        XCTAssertEqual(Season(day: 180), .autumn)
        XCTAssertEqual(Season(day: 270), .winter)
        XCTAssertEqual(Season(day: 360), .spring)
    }

    func testSeasonProgressRunsZeroToOne() {
        XCTAssertEqual(Season.progress(0), 0, accuracy: 0.001)
        XCTAssertEqual(Season.progress(89), 89.0 / 90.0, accuracy: 0.001)
    }

    func testWinterHasNoForage() {
        XCTAssertEqual(Season.winter.forageMultiplier, 0)
        XCTAssertGreaterThan(Season.summer.forageMultiplier, Season.spring.forageMultiplier)
    }

    func testBeesDoNotFlyInBadConditions() {
        XCTAssertFalse(Weather(sky: .storm, temperatureCelsius: 25).isFlyingWeather)
        XCTAssertFalse(Weather(sky: .clear, temperatureCelsius: 5).isFlyingWeather)
        XCTAssertFalse(Weather(sky: .clear, temperatureCelsius: 25, windSpeed: 15).isFlyingWeather)
        XCTAssertTrue(Weather(sky: .clear, temperatureCelsius: 25, windSpeed: 2).isFlyingWeather)
    }

    func testForageFactorIsZeroWhenGrounded() {
        XCTAssertEqual(Weather(sky: .storm, temperatureCelsius: 25).forageFactor, 0)
    }

    func testRainSuppressesButDoesNotStopForaging() {
        let rain = Weather(sky: .rain, temperatureCelsius: 18, windSpeed: 3)
        let clear = Weather(sky: .clear, temperatureCelsius: 18, windSpeed: 3)
        XCTAssertGreaterThan(rain.forageFactor, 0)
        XCTAssertLessThan(rain.forageFactor, clear.forageFactor)
    }

    func testWeatherPersistsRatherThanFlickering() {
        var rng = SeededRandom(seed: 1)
        var weather = Weather(sky: .rain, temperatureCelsius: 14)

        var sameSkyDays = 0
        for _ in 0..<200 {
            let next = Weather.next(after: weather, season: .spring, rng: &rng)
            if next.sky == weather.sky { sameSkyDays += 1 }
            weather = next
        }

        XCTAssertGreaterThan(sameSkyDays, 100, "weather is flickering randomly day to day")
    }

    func testWeatherStaysWithinSeasonalBounds() {
        var rng = SeededRandom(seed: 2)
        var weather = Weather()

        for _ in 0..<500 {
            weather = Weather.next(after: weather, season: .winter, rng: &rng)
            XCTAssertGreaterThan(weather.temperatureCelsius, -25)
            XCTAssertLessThan(weather.temperatureCelsius, 20)
            XCTAssertGreaterThanOrEqual(weather.humidity, 0)
            XCTAssertLessThanOrEqual(weather.humidity, 1.01)
        }
    }

    func testWeightedChoiceRespectsWeights() {
        var rng = SeededRandom(seed: 3)
        let choice = WeightedChoice([(Sky.clear, 9.0), (Sky.storm, 1.0)])

        var clearCount = 0
        for _ in 0..<1000 where choice.sample(&rng) == .clear { clearCount += 1 }

        XCTAssertGreaterThan(clearCount, 820)
        XCTAssertLessThan(clearCount, 980)
    }

    func testSeededRandomIsUniform() {
        var rng = SeededRandom(seed: 99)
        var sum = 0.0
        let samples = 20_000
        for _ in 0..<samples { sum += rng.unitValue() }

        XCTAssertEqual(sum / Double(samples), 0.5, accuracy: 0.02)
    }

    func testSeededRandomStaysInRange() {
        var rng = SeededRandom(seed: 5)
        for _ in 0..<10_000 {
            let value = rng.unitValue()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }
}
