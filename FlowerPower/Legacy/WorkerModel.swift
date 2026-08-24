//
//  WorkerModel.swift
//  FlowerPower
//
//  Created by Kyle Peterson on 11/10/23.
//

import Foundation

class Worker: Bee {
    var jobs: Set<WorkerJob> = []
    
    override var age: Int {
        didSet {
            if developmentStage == .adult {
                assignJobs()
            }
        }
    }

    init(age: Int = 0) {
        super.init(type: .worker, age: age)
        assignJobs()
    }

    // Function to assign and update jobs based on worker bee's age
    func assignJobs() {
        // Clear existing jobs
        jobs.removeAll()

        switch age {
        case 0..<2:
            jobs.insert(.cellCleaner)
        case 2..<11:
            jobs.insert(.nurseBee)
        case 3..<16:
            jobs.insert(.mortuary)
        case 4..<13:
            jobs.insert(.droneFeeder)
        case 7..<13:
            jobs.insert(.queenAttendant)
        case 11..<20:
            jobs.insert(.nectarConcentrator)
            jobs.insert(.pollenPacker)
        case 12..<35:
            jobs.insert(.honeycombBuilder)
            jobs.insert(.fanning)
            jobs.insert(.waterCarrier)
        case 18..<21:
            jobs.insert(.guardBee)
        case 22..<42:
            jobs.insert(.foragingBee)
        default:
            break
        }
    }
}

enum WorkerJob {
    case cellCleaner
    case nurseBee
    case mortuary
    case droneFeeder
    case queenAttendant
    case nectarConcentrator
    case pollenPacker
    case honeycombBuilder
    case fanning
    case waterCarrier
    case guardBee
    case foragingBee
}
