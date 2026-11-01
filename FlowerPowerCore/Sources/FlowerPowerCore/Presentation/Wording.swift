//
//  Wording.swift
//  FlowerPowerCore
//
//  Small pieces of English, for the engine's sentences and the interface's.
//

import Foundation

extension Int {

    /// "1 day", "3 days". The string catalogue has no plural variants, and
    /// "1 days" had been written out by hand in thirty places.
    public func counted(_ singular: String, plural: String? = nil) -> String {
        "\(self) \(self == 1 ? singular : plural ?? singular + "s")"
    }
}

extension String {

    /// The start of a sentence.
    public var capitalisingFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
