//
//  FloralTraits.swift
//  FlowerPowerCore
//
//  What a flower offers, and whether a honey bee can get at it.
//
//  Forage used to be two abstract numbers per species, `nectarRichness` and
//  `pollenRichness`, chosen to feel right. These are the measurable properties
//  those numbers were standing in for, and they behave differently from a
//  single fudge factor in ways that matter:
//
//  **Depth gates access.** A honey bee's proboscis is about 6.4 mm, and she
//  can push her head roughly 1.4 mm into a corolla, so her reach is a little
//  under 8 mm. Red clover's tube is 9–10 mm and that one fact is why white
//  clover is the classic honey plant and red clover is not, despite the two
//  being the same genus with similar nectar. Foxglove, at over 20 mm, is a
//  bumblebee flower that a honey bee can only rob. Modelling depth rather than
//  a yield multiplier is what makes the family a plant belongs to mean
//  something.
//
//  **Sugar concentration is not volume.** Nectar runs from about 15% to 60%
//  sugar by weight. A colony ripens honey by driving water off, so a litre of
//  thin nectar and a litre of thick nectar are very different amounts of work
//  and very different amounts of honey. Ivy, at nearly 50%, is worth more per
//  trip than its volume suggests.
//
//  **Pollen is protein, and protein has a composition.** Crude protein runs
//  from about 12% to 30%. But quantity is not the whole story: dandelion
//  pollen is measurably deficient in arginine, isoleucine, leucine and valine,
//  and colonies fed on it alone rear brood poorly however much of it they
//  collect. That is a real and well-documented effect, and it is the reason a
//  monoculture is dangerous to a colony in a way that a shortage is not.
//
//  Some plants offer only one of the two. Poppies produce no nectar at all and
//  vast quantities of pollen; meadowsweet is the same. A model with a single
//  richness number cannot express that, and got both plants wrong.
//

import Foundation

// MARK: - The bee's end of it

public enum BeeMorphology {

    /// Worker honey bee proboscis, in millimetres. Measurements cluster around
    /// 6.3–6.6 for *Apis mellifera*, longer in some races.
    public static let proboscisLengthMillimetres = 6.4

    /// How far a bee can push her head into a corolla, which genuinely extends
    /// her reach and is why the naive tongue-length comparison is too harsh.
    public static let headInsertionMillimetres = 1.4

    public static var nectarReachMillimetres: Double {
        proboscisLengthMillimetres + headInsertionMillimetres
    }

    /// How far past her reach a bee can still extract *something*.
    ///
    /// Not zero, because nectar rises in a narrow tube by capillary action and
    /// a well-filled flower presents its nectar higher than an empty one. It
    /// is why honey bees do work red clover in a heavy flow, and take almost
    /// nothing from it otherwise.
    public static let reachToleranceMillimetres = 2.5
}

// MARK: - The flower's end of it

public struct FloralTraits: Codable, Hashable, Sendable {

    /// Depth of the corolla tube in millimetres, from the opening to where the
    /// nectar sits. Zero for an open flower with exposed nectaries.
    public var corollaDepthMillimetres: Double

    /// Sugar as a fraction of nectar weight, 0...1. Around 0.15 for the
    /// thinnest, 0.60 for the thickest.
    public var nectarSugarConcentration: Double

    /// Nectar produced per flower per day, relative to an ordinary flower.
    public var nectarVolume: Double

    /// Crude protein as a fraction of pollen weight, 0...1. Roughly 0.12 to
    /// 0.30 across the plants a colony works.
    public var pollenProteinFraction: Double

    /// How complete the essential amino acid profile is, 0...1. Below 1 the
    /// pollen cannot fully support brood rearing however much is collected.
    public var pollenAminoAcidCompleteness: Double

    /// Pollen produced, relative to an ordinary flower. Willow and poppy are
    /// extraordinary; many deep tubular flowers offer very little.
    public var pollenAbundance: Double

    /// Some plants offer none at all.
    public var producesNectar: Bool

    public init(
        corollaDepthMillimetres: Double,
        nectarSugarConcentration: Double,
        nectarVolume: Double,
        pollenProteinFraction: Double,
        pollenAminoAcidCompleteness: Double,
        pollenAbundance: Double,
        producesNectar: Bool = true
    ) {
        self.corollaDepthMillimetres = max(0, corollaDepthMillimetres)
        self.nectarSugarConcentration = min(1, max(0, nectarSugarConcentration))
        self.nectarVolume = max(0, nectarVolume)
        self.pollenProteinFraction = min(1, max(0, pollenProteinFraction))
        self.pollenAminoAcidCompleteness = min(1, max(0, pollenAminoAcidCompleteness))
        self.pollenAbundance = max(0, pollenAbundance)
        self.producesNectar = producesNectar
    }

    // MARK: - Derived

    /// How much of this flower's nectar a honey bee can actually reach, 0...1.
    ///
    /// Full access while the nectar is within her reach, falling to nothing
    /// over the couple of millimetres past it where capillary rise and a
    /// well-filled flower can still bring nectar within range.
    public var nectarAccessibility: Double {
        guard producesNectar else { return 0 }

        let reach = BeeMorphology.nectarReachMillimetres
        guard corollaDepthMillimetres > reach else { return 1 }

        let beyond = corollaDepthMillimetres - reach
        return max(0, 1 - beyond / BeeMorphology.reachToleranceMillimetres)
    }

    /// Whether a honey bee is essentially locked out. The interface should say
    /// so rather than leaving a player wondering why nothing is happening.
    public var isOutOfReach: Bool { nectarAccessibility <= 0.05 }

    /// Nectar a colony can actually take from this flower, relative to an
    /// ordinary one. Volume, gated by whether she can reach it.
    public var effectiveNectarYield: Double {
        producesNectar ? nectarVolume * nectarAccessibility : 0
    }

    /// Sugar actually banked per unit of nectar gathered.
    ///
    /// This is what makes thin nectar expensive: the water has to be driven
    /// off before it will keep, and the colony fans for it.
    public var sugarYield: Double {
        effectiveNectarYield * nectarSugarConcentration
    }

    /// Pollen a colony can use, relative to an ordinary flower.
    ///
    /// Abundance times protein content times how usable that protein is.
    /// Dandelion collects well and rears badly, and this is where that lives.
    public var effectivePollenYield: Double {
        // Scaled against a nominal 20% crude protein so an ordinary flower
        // comes out near 1 and the numbers stay readable.
        pollenAbundance
            * (pollenProteinFraction / Self.referenceProteinFraction)
            * pollenAminoAcidCompleteness
    }

    /// Sugar yield of an average catalogue flower, used to express nectar in
    /// units where an ordinary flower is 1.
    ///
    /// Measured from the catalogue rather than picked (`beesim --scale`
    /// reports it), because every consumption constant in the engine — what a
    /// colony burns, what it needs for winter, what counts as a flow — was
    /// calibrated against a forage scale where the mean flower is 1. Deriving
    /// nectar from real traits changed the size of the unit; normalising to
    /// the catalogue mean is what keeps that calibration valid without
    /// touching a single relative value.
    ///
    /// `CatalogueScaleTests` fails if the catalogue drifts away from it.
    public static let referenceSugarYield = 0.4128

    /// Reference crude protein, on the same principle. This one needed no
    /// adjustment: the catalogue's mean pollen richness came out at 1.005.
    public static let referenceProteinFraction = 0.20

    /// Nutritional quality of the pollen alone, 0...1-ish, independent of how
    /// much there is. Brood rearing depends on this rather than on bulk.
    public var pollenQuality: Double {
        (pollenProteinFraction / 0.25) * pollenAminoAcidCompleteness
    }
}
