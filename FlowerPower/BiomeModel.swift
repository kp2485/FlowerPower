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
    case cacti(flowering: Bool = false, cavityProbability: Double = 0.1)
    case alpineFlowers(flowering: Bool = true, cavityProbability: Double = 0.0)
    case waterLilies(flowering: Bool = true, cavityProbability: Double = 0.0)
}



enum AnimalType {
    // Non-predators
    case deer(isPredator: Bool = false)
    case rabbits(isPredator: Bool = false)
    case squirrels(isPredator: Bool = false)
    case bison(isPredator: Bool = false)
    case pronghorn(isPredator: Bool = false)
    case coyotes(isPredator: Bool = false)
    
    // Bee predators
    case snakes(isPredator: Bool = true)
    case honeyBuzzard(isPredator: Bool = true)
    case human(isPredator: Bool = true)
    case bears(isPredator: Bool = true)
    case skunks(isPredator: Bool = true)
    case raccoons(isPredator: Bool = true)
    case mice(isPredator: Bool = true)
    case beeEaters(isPredator: Bool = true)
    case honeyGuides(isPredator: Bool = true)
    case nuthatches(isPredator: Bool = true)
    case flyCatchers(isPredator: Bool = true)
    case woodpeckers(isPredator: Bool = true)
    case wasps(isPredator: Bool = true)
    case mites(isPredator: Bool = true)
    case preyingMantis(isPredator: Bool = true)
    case dragonflies(isPredator: Bool = true)
    case cockroaches(isPredator: Bool = true)
    case earwigs(isPredator: Bool = true)
    case ants(isPredator: Bool = true)
    case waxMoths(isPredator: Bool = true)
    case crabSpiders(isPredator: Bool = true)
    case hiveBeetles(isPredator: Bool = true)
    case killerBees(isPredator: Bool = true)
    case honeyBadgers(isPredator: Bool = true)
    case opossums(isPredator: Bool = true)
    case mountainLions(isPredator: Bool = true)
}

