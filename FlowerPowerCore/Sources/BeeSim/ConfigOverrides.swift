//
//  ConfigOverrides.swift
//  BeeSim
//
//  Lets `--set knob=value` sweep a balance constant without a rebuild.
//
//  Deliberately part of the tool rather than the engine: the simulation has no
//  business looking constants up by string, and keeping this here means the
//  engine's config stays a plain struct of typed values.
//
//  An unknown key is a hard error rather than a no-op. A silently ignored
//  override would produce a sweep whose rows all secretly used the same value,
//  which is exactly the sort of measurement that sends balance work down a
//  blind alley.
//

import Foundation
import FlowerPowerCore

extension SimulationConfig {

    mutating func apply(_ key: String, _ value: Double) {
        switch key {

        // Foraging
        case "nectarPerForager": nectarPerForager = value
        case "pollenPerForager": pollenPerForager = value
        case "danceRecruitmentExponent": danceRecruitmentExponent = value
        case "patchDailyRegrowth": patchDailyRegrowth = value
        case "flightEnergyPerForager": flightEnergyPerForager = value
        case "forageWearPerTick": forageWearPerTick = value

        case "flowThresholdPerBee": flowThresholdPerBee = value
        case "dearthThresholdPerBee": dearthThresholdPerBee = value
        case "sharedPatchYield": sharedPatchYield = value
        case "patchFreshDays": patchFreshDays = Int(value)
        case "patchFadeDays": patchFadeDays = Int(value)

        // Comb
        case "buildCongestionThreshold": buildCongestionThreshold = value
        case "buildHoneyReserve": buildHoneyReserve = value
        case "cellsPerBuilderPerTick": cellsPerBuilderPerTick = value
        case "waxPerBuilder": waxPerBuilder = value
        case "honeyPerWax": honeyPerWax = value

        // Swarming and pheromones
        case "swarmProvisionMultiple": swarmProvisionMultiple = value
        case "swarmSeasonStart": swarmSeasonStart = value
        case "swarmSeasonEnd": swarmSeasonEnd = value
        case "swarmCongestionThreshold": swarmCongestionThreshold = value
        case "swarmCellChance": swarmCellChance = value
        case "swarmDepartureShare": swarmDepartureShare = value
        case "swarmMinimumPopulation": swarmMinimumPopulation = Int(value)
        case "pheromoneDilutionScale": pheromoneDilutionScale = value
        case "queenPheromoneOutput": queenPheromoneOutput = value
        case "supersedureChance": supersedureChance = value

        // Winter provisioning
        case "autumnIncomeOptimism": autumnIncomeOptimism = value
        case "winterProvisioningMargin": winterProvisioningMargin = value
        case "winterBuildUpStart": winterBuildUpStart = value

        // Brood and queen
        case "maxEggsPerDay": maxEggsPerDay = Int(value)
        case "broodPerNurse": broodPerNurse = value
        case "layingReservePerBee": layingReservePerBee = value
        case "layingEnergyThreshold": layingEnergyThreshold = value
        case "queenFailureVitality": queenFailureVitality = value

        // Disease and threats
        case "pathogenArrivalMultiplier": pathogenArrivalMultiplier = value
        case "pathogenSeedLevel": pathogenSeedLevel = value
        case "pathogenBaseRecovery": pathogenBaseRecovery = value
        case "hygienicRemovalRate": hygienicRemovalRate = value
        case "viralBroodDamage": viralBroodDamage = value
        case "criticalInfectionLevel": criticalInfectionLevel = value
        case "predatorStrength": predatorStrength = value

        default:
            FileHandle.standardError.write(
                Data("beesim: unknown --set key '\(key)'\n".utf8)
            )
            exit(2)
        }
    }
}
