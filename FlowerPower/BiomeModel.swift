//
//  BiomeModel.swift
//  FlowerPower
//
//  Created by Kyle Peterson on 11/12/23.
//

import Foundation

class Biome {
    var name: String
    var terrain: TerrainType
    var climate: ClimateType
    var environmentalFeatures: [EnvironmentalFeature]
    var flora: [PlantType]
    var fauna: [AnimalType]
    
    init(name: String, terrain: TerrainType, environmentalFeatures: [EnvironmentalFeature], climate: ClimateType, flora: [PlantType], fauna: [AnimalType]) {
        self.name = name
        self.terrain = terrain
        self.environmentalFeatures = environmentalFeatures
        self.climate = climate
        self.flora = flora
        self.fauna = fauna
    }
}

enum TerrainType {
    case forest
    case grassland
    case desert
    case mountain
    case wetland
}

enum EnvironmentalFeature {
    case clearing(cavityProbability: Double = 0.0)
    case pond(cavityProbability: Double = 0.0)
    case stream(cavityProbability: Double = 0.0)
    case rockOutcropping(cavityProbability: Double = 0.5)
    case waterfall(cavityProbability: Double = 0.0)
    case cave(cavityProbability: Double = 1.0)
    case house(cavityProbability: Double = 1.0)
    case garage(cavityProbability: Double = 1.0)
    case shed(cavityProbability: Double = 1.0)
    case barn(cavityProbability: Double = 1.0)
}

enum ClimateType {
    case mild
    case seasonal
    case arid
    case cold
    case humid
    case tropical
    case alpine
}

enum PlantType {
    case oak(flowering: Bool = false, cavityProbability: Double = 0.1)
    case maple(flowering: Bool = false, cavityProbability: Double = 0.1)
    case cactus(flowering: Bool = true, cavityProbability: Double = 0.1)
    case alpineFlower(flowering: Bool = true, cavityProbability: Double = 0.0)
    case waterLily(flowering: Bool = true, cavityProbability: Double = 0.0)
}



enum AnimalType: CustomStringConvertible {
    // Non-predators
    case deer(isPredator: Bool = false)
    case rabbit(isPredator: Bool = false)
    case squirrel(isPredator: Bool = false)
    case bison(isPredator: Bool = false)
    case pronghorn(isPredator: Bool = false)
    case coyote(isPredator: Bool = false)
    
    // Bee predators
    case snake(isPredator: Bool = true)
    case honeyBuzzard(isPredator: Bool = true)
    case human(isPredator: Bool = true)
    case bear(isPredator: Bool = true)
    case skunk(isPredator: Bool = true)
    case raccoon(isPredator: Bool = true)
    case mouse(isPredator: Bool = true)
    case beeEater(isPredator: Bool = true)
    case honeyGuide(isPredator: Bool = true)
    case nuthatch(isPredator: Bool = true)
    case flyCatcher(isPredator: Bool = true)
    case woodpecker(isPredator: Bool = true)
    case wasp(isPredator: Bool = true)
    case mite(isPredator: Bool = true)
    case preyingMantis(isPredator: Bool = true)
    case dragonfly(isPredator: Bool = true)
    case cockroach(isPredator: Bool = true)
    case earwig(isPredator: Bool = true)
    case ant(isPredator: Bool = true)
    case waxMoth(isPredator: Bool = true)
    case crabSpider(isPredator: Bool = true)
    case hiveBeetle(isPredator: Bool = true)
    case killerBee(isPredator: Bool = true)
    case honeyBadger(isPredator: Bool = true)
    case opossum(isPredator: Bool = true)
    case mountainLion(isPredator: Bool = true)
    
    var description: String {
        switch self {
        case .deer: return "Deer"
        case .rabbit: return "Rabbit"
        case .squirrel: return "Squirrel"
        case .bison: return "Bison"
        case .pronghorn: return "Pronghorn"
        case .coyote: return "Coyote"
        case .snake: return "Snake"
        case .honeyBuzzard: return "Honey Buzzard"
        case .human: return "Human"
        case .bear: return "Bear"
        case .skunk: return "Skunk"
        case .raccoon: return "Raccoon"
        case .mouse: return "Mouse"
        case .beeEater: return "Bee Eater"
        case .honeyGuide: return "Honey Guide"
        case .nuthatch: return "Nuthatch"
        case .flyCatcher: return "Fly Catcher"
        case .woodpecker: return "Woodpecker"
        case .wasp: return "Wasp"
        case .mite: return "Mite"
        case .preyingMantis: return "Preying Mantis"
        case .dragonfly: return "Dragonfly"
        case .cockroach: return "Cockroach"
        case .earwig: return "Earwig"
        case .ant: return "Ant"
        case .waxMoth: return "Wax Moth"
        case .crabSpider: return "Crab Spider"
        case .hiveBeetle: return "Hive Beetle"
        case .killerBee: return "Killer Bee"
        case .honeyBadger: return "Honey Badger"
        case .opossum: return "Opossum"
        case .mountainLion: return "Mountain Lion"
        }
    }
}
