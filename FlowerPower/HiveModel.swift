//
//  HiveModel.swift
//  FlowerPower
//
//  Created by Kyle Peterson on 11/10/23.
//

import Foundation

class Hive: ObservableObject {
    var cells: [HiveCell]
    
    init(hiveLocation: HiveLocation, numberOfCells: Int) {
        self.cells = Array(repeating: HiveCell(), count: numberOfCells)
    }
    
    // Function and computed properties for counting queens in each development stage
    private func countBees<T: Bee>(_ criteria: (T) -> Bool) -> Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, let typedBee = bee as? T, criteria(typedBee) {
                return result + 1
            }
            return result
        }
    }
    
    var queensInEggStage: Int {
        return countBees { $0.type == .queen && $0.developmentStage == .egg }
    }
    
    var queensInLarvaStage: Int {
        return countBees { $0.type == .queen && $0.developmentStage == .larva }
    }
    
    var queensInPupaStage: Int {
        return countBees { $0.type == .queen && $0.developmentStage == .pupa }
    }
    
    var queensInAdultStage: Int {
        return countBees { $0.type == .queen && $0.developmentStage == .adult }
    }
    
    var dronesInEggStage: Int {
        return countBees { $0.type == .drone && $0.developmentStage == .egg }
    }
    
    var dronesInLarvaStage: Int {
        return countBees { $0.type == .drone && $0.developmentStage == .larva }
    }
    
    var dronesInPupaStage: Int {
        return countBees { $0.type == .drone && $0.developmentStage == .pupa }
    }
    
    var dronesInAdultStage: Int {
        return countBees { $0.type == .drone && $0.developmentStage == .adult }
    }
    
    var workersInEggStage: Int {
        return countBees { $0.type == .worker && $0.developmentStage == .egg }
    }
    
    var workersInLarvaStage: Int {
        return countBees { $0.type == .worker && $0.developmentStage == .larva }
    }
    
    var workersInPupaStage: Int {
        return countBees { $0.type == .worker && $0.developmentStage == .pupa }
    }
    
    var workersInAdultStage: Int {
        return countBees { $0.type == .worker && $0.developmentStage == .adult }
    }
    
    // Function and computed properties for counting worker jobs
    private func countWorkerBees(withJob job: WorkerJob) -> Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, bee.developmentStage == .adult, let worker = bee as? Worker, worker.jobs.contains(job) {
                return result + 1
            }
            return result
        }
    }
    
    var totalCellCleaners: Int {
        return countWorkerBees(withJob: .cellCleaner)
    }
    
    var totalNurseBees: Int {
        return countWorkerBees(withJob: .nurseBee)
    }
    
    var totalMortuaryBees: Int {
        return countWorkerBees(withJob: .mortuary)
    }
    
    var totalDroneFeeders: Int {
        return countWorkerBees(withJob: .droneFeeder)
    }
    
    var totalQueenAttendants: Int {
        return countWorkerBees(withJob: .queenAttendant)
    }
    
    var totalNectarConcentrators: Int {
        return countWorkerBees(withJob: .nectarConcentrator)
    }
    
    var totalPollenPackers: Int {
        return countWorkerBees(withJob: .pollenPacker)
    }
    
    var totalHoneycombBuilders: Int {
        return countWorkerBees(withJob: .honeycombBuilder)
    }
    
    var totalFanningBees: Int {
        return countWorkerBees(withJob: .fanning)
    }
    
    var totalWaterCarriers: Int {
        return countWorkerBees(withJob: .waterCarrier)
    }
    
    var totalGuardBees: Int {
        return countWorkerBees(withJob: .guardBee)
    }
    
    var totalForagingBees: Int {
        return countWorkerBees(withJob: .foragingBee)
    }
    
    // Function and computed properties for counting resources
    private func countResources(resourceType: ResourceType) -> Int {
        return cells.reduce(0) { result, cell in
            if case .resource(resourceType, let quantity) = cell.contents {
                return result + quantity
            }
            return result
        }
    }
    
    var totalNectar: Int {
        return countResources(resourceType: .nectar)
    }
    
    var totalPollen: Int {
        return countResources(resourceType: .pollen)
    }
    
    var totalWater: Int {
        return countResources(resourceType: .water)
    }
    
    var totalPropolis: Int {
        return countResources(resourceType: .propolis)
    }
    
    var totalWax: Int {
        return countResources(resourceType: .wax)
    }
    
    var totalRoyalJelly: Int {
        return countResources(resourceType: .royalJelly)
    }
    
    // Add functions for managing the cells, such as placing bees, larvae, pupae, and resources into the cells.
}

class HiveCell {
    var contents: HiveCellContents = .empty
    
    enum HiveCellContents {
        case empty
        case bee(Bee)
        case resource(ResourceType, Int)
    }
}

struct HiveLocation {
    var coordinates: (x: Double, y: Double)
    var locationType: HiveLocationType
}

enum HiveLocationType {
    case livingTreeCavity
    case fallenTree
    case underTreeBranch
    case cliff
    case cave
    case insideWalls
    case humanStructure
    case termiteMound
    case animalBurrow
    case nestbox
}

enum ResourceType {
    case nectar
    case pollen
    case water
    case propolis
    case wax
    case royalJelly
}
