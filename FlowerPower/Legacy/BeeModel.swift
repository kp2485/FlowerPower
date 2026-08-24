//
//  BeeModel.swift
//  FlowerPower
//
//  Created by Kyle Peterson on 11/10/23.
//

import Foundation

class Bee {
    var type: BeeType
    var age: Int
    var developmentStage: BeeDevelopmentStage
    var isAlive: Bool = true
    
    init(type: BeeType, age: Int = 0) {
        self.type = type
        self.age = age
        self.developmentStage = .egg
    }
    
    func advanceDevelopmentStage() {
        switch developmentStage {
        case .egg:
            developmentStage = .larva
            age = 0
        case .larva:
            developmentStage = .pupa
            age = 0
        case .pupa:
            developmentStage = .adult
            age = 0
        case .adult:
            isAlive = false
        }
    }
}

enum BeeType: String {
    case queen
    case worker
    case drone
    
    var lifespan: Int {
        switch self {
        case .queen: return 365 // 1-2 years
        case .worker: return 42 // 6 weeks (summer), 5-7 months (winter)
        case .drone: return 55 // 55 days
        }
    }
}

enum BeeDevelopmentStage {
    case egg
    case larva
    case pupa
    case adult
}
