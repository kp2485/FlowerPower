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
    
    // Computed properties for counting queens in each development stage
        var queensInEggStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .queen, bee.developmentStage == .egg {
                    return result + 1
                }
                return result
            }
        }

        var queensInLarvaStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .queen, bee.developmentStage == .larva {
                    return result + 1
                }
                return result
            }
        }

        var queensInPupaStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .queen, bee.developmentStage == .pupa {
                    return result + 1
                }
                return result
            }
        }

        var queensInAdultStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .queen, bee.developmentStage == .adult {
                    return result + 1
                }
                return result
            }
        }

        // Computed properties for counting drones in each development stage
        var dronesInEggStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .drone, bee.developmentStage == .egg {
                    return result + 1
                }
                return result
            }
        }

        var dronesInLarvaStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .drone, bee.developmentStage == .larva {
                    return result + 1
                }
                return result
            }
        }

        var dronesInPupaStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .drone, bee.developmentStage == .pupa {
                    return result + 1
                }
                return result
            }
        }

        var dronesInAdultStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .drone, bee.developmentStage == .adult {
                    return result + 1
                }
                return result
            }
        }

        // Computed properties for counting workers in each development stage
        var workersInEggStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .worker, bee.developmentStage == .egg {
                    return result + 1
                }
                return result
            }
        }

        var workersInLarvaStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .worker, bee.developmentStage == .larva {
                    return result + 1
                }
                return result
            }
        }

        var workersInPupaStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .worker, bee.developmentStage == .pupa {
                    return result + 1
                }
                return result
            }
        }

        var workersInAdultStage: Int {
            return cells.reduce(0) { result, cell in
                if case .bee(let bee) = cell.contents, bee.type == .worker, bee.developmentStage == .adult {
                    return result + 1
                }
                return result
            }
        }
    
    // Computed properties for counting worker jobs
    var totalCellCleaners: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.cellCleaner) {
                return result + 1
            }
            return result
        }
    }

    var totalNurseBees: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.nurseBee) {
                return result + 1
            }
            return result
        }
    }

    var totalMortuaryBees: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.mortuary) {
                return result + 1
            }
            return result
        }
    }

    var totalDroneFeeders: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.droneFeeder) {
                return result + 1
            }
            return result
        }
    }

    var totalQueenAttendants: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.queenAttendant) {
                return result + 1
            }
            return result
        }
    }

    var totalNectarConcentrators: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.nectarConcentrator) {
                return result + 1
            }
            return result
        }
    }

    var totalPollenPackers: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.pollenPacker) {
                return result + 1
            }
            return result
        }
    }

    var totalHoneycombBuilders: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.honeycombBuilder) {
                return result + 1
            }
            return result
        }
    }

    var totalFanningBees: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.fanning) {
                return result + 1
            }
            return result
        }
    }

    var totalWaterCarriers: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.waterCarrier) {
                return result + 1
            }
            return result
        }
    }

    var totalGuardBees: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.guardBee) {
                return result + 1
            }
            return result
        }
    }

    var totalForagingBees: Int {
        return cells.reduce(0) { result, cell in
            if case .bee(let bee) = cell.contents, bee.type == .worker, let worker = bee as? Worker, worker.jobs.contains(.foragingBee) {
                return result + 1
            }
            return result
        }
    }

    // Computed properties for counting resources
    var totalNectar: Int {
        return cells.reduce(0) { result, cell in
            if case .resource(.nectar, let quantity) = cell.contents {
                return result + quantity
            }
            return result
        }
    }

    var totalPollen: Int {
        return cells.reduce(0) { result, cell in
            if case .resource(.pollen, let quantity) = cell.contents {
                return result + quantity
            }
            return result
        }
    }

    var totalWater: Int {
        return cells.reduce(0) { result, cell in
            if case .resource(.water, let quantity) = cell.contents {
                return result + quantity
            }
            return result
        }
    }

    var totalPropolis: Int {
        return cells.reduce(0) { result, cell in
            if case .resource(.propolis, let quantity) = cell.contents {
                return result + quantity
            }
            return result
        }
    }

    var totalWax: Int {
        return cells.reduce(0) { result, cell in
            if case .resource(.wax, let quantity) = cell.contents {
                return result + quantity
            }
            return result
        }
    }

    var totalRoyalJelly: Int {
        return cells.reduce(0) { result, cell in
            if case .resource(.royalJelly, let quantity) = cell.contents {
                return result + quantity
            }
            return result
        }
    }
    
    // Add functions for managing the cells, such as placing bees, larvae, pupae, and resources into the cells.
}

class HiveCell {
    var contents: HiveCellContents = .empty
    
    enum HiveCellContents {
        case empty
        case bee(Bee)
        case resource(ResourceType, Int) // e.g., resource type and quantity
    }
}

struct HiveLocation {
    var coordinates: (x: Double, y: Double)
    var type: HiveType
}

enum HiveType {
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

