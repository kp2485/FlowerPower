//
//  ClassifierLabels.swift
//  FlowerPowerCore
//
//  Turning whatever a trained model says into a species the game knows.
//
//  A Core ML classifier emits the class names of the dataset it was trained
//  on, and those will not be our identifiers. Worse, they will not even be one
//  consistent vocabulary: "corn poppy" from one dataset, "Papaver rhoeas" from
//  another, "common poppy" from a third, all meaning the flower this catalogue
//  calls `poppy`.
//
//  So there is a table. It is written in terms of real botanical synonyms
//  rather than one dataset's spellings, which means retraining on a different
//  source does not invalidate it.
//
//  On matching by substring
//
//  The first version of `match(label:)` fell back to a plain `contains` in
//  both directions, which is a trap waiting for a short common name. This
//  catalogue has `Ivy` in it, so *any* label containing those three letters —
//  "poison ivy", "Boston ivy", "ivy-leaved toadflax", none of them Hedera
//  helix and none of them worth a bee's time — resolved to the ivy that
//  carries colonies through October. Matching is now on whole words, and
//  substring matching needs a label long enough for the coincidence to be
//  unlikely.
//

import Foundation

public enum ClassifierLabels {

    /// Known names for each catalogue species, lower-cased, in the spellings
    /// datasets actually use. Scientific names first, then common synonyms.
    ///
    /// Only aliases that are unambiguously the same plant. A near relative is
    /// not a match: creeping thistle and spear thistle are both `thistle` here
    /// because the game does not distinguish them and a bee does not either,
    /// but Canterbury bells is not `bluebell`, however much the name suggests
    /// it, because it is a different genus entirely.
    public static let aliases: [String: [String]] = [
        "crocus": ["crocus vernus", "spring crocus", "dutch crocus", "crocus"],
        "willow": ["salix caprea", "goat willow", "pussy willow", "sallow", "great sallow"],
        "dandelion": ["taraxacum officinale", "taraxacum", "common dandelion"],
        "apple": ["malus domestica", "malus", "apple blossom", "apple tree"],
        "hawthorn": ["crataegus monogyna", "crataegus", "may blossom", "whitethorn", "quickthorn"],
        "oilseed_rape": ["brassica napus", "rapeseed", "rape seed", "canola", "oilseed rape"],
        "bluebell": [
            "hyacinthoides non-scripta", "hyacinthoides", "common bluebell",
            "english bluebell", "wild hyacinth"
        ],
        "cherry": ["prunus avium", "wild cherry", "sweet cherry", "cherry blossom", "gean"],
        "white_clover": ["trifolium repens", "trifolium", "white clover", "dutch clover"],
        "borage": ["borago officinalis", "borage", "starflower"],
        "lavender": ["lavandula angustifolia", "lavandula", "english lavender", "true lavender"],
        "bramble": ["rubus fruticosus", "rubus", "blackberry", "bramble"],
        "lime": ["tilia europaea", "tilia", "linden", "lime tree", "basswood"],
        "phacelia": [
            "phacelia tanacetifolia", "phacelia", "lacy phacelia",
            "purple tansy", "fiddleneck"
        ],
        "sunflower": ["helianthus annuus", "helianthus", "common sunflower"],
        "thistle": [
            "cirsium arvense", "cirsium vulgare", "cirsium", "creeping thistle",
            "spear thistle", "field thistle"
        ],
        "foxglove": ["digitalis purpurea", "digitalis", "common foxglove"],
        "poppy": [
            "papaver rhoeas", "papaver", "corn poppy", "common poppy",
            "field poppy", "flanders poppy", "red poppy"
        ],
        "echinacea": ["echinacea purpurea", "echinacea", "purple coneflower", "coneflower"],
        "rosemary": ["salvia rosmarinus", "rosmarinus officinalis", "rosemary"],
        "heather": ["calluna vulgaris", "calluna", "ling", "common heather", "scots heather"],
        "ivy": ["hedera helix", "hedera", "common ivy", "english ivy"],
        "balsam": [
            "impatiens glandulifera", "himalayan balsam", "indian balsam",
            "policeman's helmet"
        ],
        "goldenrod": ["solidago virgaurea", "solidago", "european goldenrod", "woundwort"],
        "aster": [
            "symphyotrichum novi-belgii", "symphyotrichum", "aster novi-belgii",
            "michaelmas daisy", "new york aster"
        ],
        "sedum": [
            "hylotelephium spectabile", "sedum spectabile", "hylotelephium",
            "ice plant", "butterfly stonecrop", "showy stonecrop"
        ],
        "winter_heather": ["erica carnea", "erica", "winter heath", "spring heath", "alpine heath"],
        "mahonia": ["mahonia aquifolium", "mahonia", "oregon grape"],
        "vipers_bugloss": ["echium vulgare", "echium", "viper's bugloss", "vipers bugloss", "blueweed"],
        "meadowsweet": ["filipendula ulmaria", "filipendula", "meadowsweet", "mead wort", "queen of the meadow"]
    ]

    /// Reverse index, built once. Alias to species id.
    static let index: [String: String] = {
        var index: [String: String] = [:]
        for (speciesID, names) in aliases {
            for name in names {
                index[normalise(name)] = speciesID
            }
        }
        return index
    }()

    /// Lower-cased, underscores and hyphens flattened to spaces, collapsed
    /// runs of whitespace, no surrounding punctuation. Datasets differ on all
    /// of these and none of the differences are meaningful.
    public static func normalise(_ label: String) -> String {
        let flattened = label
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        let words = flattened
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]")) }
            .filter { !$0.isEmpty }

        return words.joined(separator: " ")
    }

    /// Whole-word containment, so "ivy" does not match "poison ivy" by
    /// accident but "common poppy" still finds "poppy".
    static func containsWholePhrase(_ phrase: String, in label: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        let words = label.components(separatedBy: " ")
        let phraseWords = phrase.components(separatedBy: " ")
        guard phraseWords.count <= words.count else { return false }

        for start in 0...(words.count - phraseWords.count)
        where Array(words[start..<(start + phraseWords.count)]) == phraseWords {
            return true
        }
        return false
    }

    /// A single word is too weak a signal to identify on by itself unless the
    /// label is essentially that word. Two-word phrases are specific enough.
    static let minimumWordsForPhraseMatch = 2
}
