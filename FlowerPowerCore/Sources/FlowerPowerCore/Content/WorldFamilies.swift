//
//  WorldFamilies.swift
//  FlowerPowerCore
//
//  Families the catalogue does not collect but the world is full of.
//
//  The identifier can name any of the four hundred and seventy families of
//  flowering plant, and most of what a player photographs in a park or a
//  garden centre — tulips, orchids, hydrangeas, petunias, peonies, magnolias —
//  belongs to none of the eighteen the game models. Those eighteen are the
//  ones a temperate honey bee colony actually lives on, and that is a
//  deliberate choice about what the collection is *for*. But a placed flower
//  still has to be given to the bees as something, and "an ordinary flower"
//  is the wrong answer for a peony (all pollen, no nectar) or an orchid (no
//  use to a honey bee at all).
//
//  So this is a second table, of what a family means to a colony, for the
//  families a player is likeliest to meet. It is notes and typical traits
//  only — none of these appear in the field guide or count toward the
//  collection, which stays the eighteen. A family in neither table gets
//  `FloralTraits.unknownFamily` and a plain sentence, which is honest.
//
//  Traits are typical values with the same caveat as `PlantFamily`'s: the
//  ordering between families matters far more than any one number. Sources
//  are the same beekeeping references the catalogue was built from — Hooper,
//  Kirk & Howes — and, for the tropical families, the honey-plant literature.
//

import Foundation

public enum WorldFamilies {

    public struct Entry: Sendable {
        public let commonName: String
        public let forageNote: String
        public let traits: FloralTraits
    }

    public static func entry(for family: BotanicalFamily) -> Entry? {
        entries[family.rawValue]
    }

    /// Families with notes, as names, for tests and for the picker.
    public static var known: [BotanicalFamily] {
        entries.keys.sorted().map(BotanicalFamily.init)
    }

    private static func traits(
        corolla: Double, sugar: Double, volume: Double,
        protein: Double, complete: Double, pollen: Double,
        nectar: Bool = true
    ) -> FloralTraits {
        FloralTraits(
            corollaDepthMillimetres: corolla,
            nectarSugarConcentration: sugar,
            nectarVolume: volume,
            pollenProteinFraction: protein,
            pollenAminoAcidCompleteness: complete,
            pollenAbundance: pollen,
            producesNectar: nectar
        )
    }

    private static let entries: [String: Entry] = [
        "ranunculaceae": Entry(
            commonName: "Buttercup Family",
            forageNote: "Open, shallow flowers with plenty of pollen. Buttercups, anemones and clematis; the nectar is modest.",
            traits: traits(corolla: 2, sugar: 0.35, volume: 0.4, protein: 0.20, complete: 0.85, pollen: 1.2)
        ),
        "caryophyllaceae": Entry(
            commonName: "Pink Family",
            forageNote: "Carnations and campions keep their nectar at the bottom of a narrow tube. Butterflies and moths do better here than bees.",
            traits: traits(corolla: 12, sugar: 0.35, volume: 0.5, protein: 0.18, complete: 0.85, pollen: 0.5)
        ),
        "liliaceae": Entry(
            commonName: "Lily Family",
            forageNote: "Tulips offer pollen and little else; true lilies more nectar, in a big open flower. Worked, but never a flow.",
            traits: traits(corolla: 8, sugar: 0.30, volume: 0.8, protein: 0.20, complete: 0.85, pollen: 1.2)
        ),
        "amaryllidaceae": Entry(
            commonName: "Amaryllis Family",
            forageNote: "Daffodils are worked for pollen on warm March days. The onions and chives in the same family are a real nectar plant in summer.",
            traits: traits(corolla: 6, sugar: 0.40, volume: 0.8, protein: 0.18, complete: 0.80, pollen: 0.9)
        ),
        "orchidaceae": Entry(
            commonName: "Orchid Family",
            forageNote: "Built for one particular pollinator each, and almost never a honey bee. Beautiful, and no use to the colony.",
            traits: traits(corolla: 15, sugar: 0.30, volume: 0.2, protein: 0.10, complete: 0.60, pollen: 0.1)
        ),
        "solanaceae": Entry(
            commonName: "Nightshade Family",
            forageNote: "Petunias and tobacco flowers are long tubes for moths. Potato and tomato flowers give pollen to bees that can shake it loose, which a honey bee cannot.",
            traits: traits(corolla: 15, sugar: 0.30, volume: 0.5, protein: 0.20, complete: 0.85, pollen: 0.6)
        ),
        "geraniaceae": Entry(
            commonName: "Geranium Family",
            forageNote: "Open flowers and easy nectar, in small amounts. Cranesbills in a border keep foragers busy through summer.",
            traits: traits(corolla: 2, sugar: 0.40, volume: 0.4, protein: 0.18, complete: 0.85, pollen: 0.6)
        ),
        "oleaceae": Entry(
            commonName: "Olive Family",
            forageNote: "Lilac and jasmine are for the nose; privet, in the same family, is a strong if rank-smelling June nectar plant.",
            traits: traits(corolla: 6, sugar: 0.35, volume: 0.6, protein: 0.18, complete: 0.85, pollen: 0.7)
        ),
        "hydrangeaceae": Entry(
            commonName: "Hydrangea Family",
            forageNote: "The showy heads are mostly sterile florets with nothing in them. The small true flowers, where a variety keeps them, give a little.",
            traits: traits(corolla: 1, sugar: 0.30, volume: 0.3, protein: 0.17, complete: 0.80, pollen: 0.5)
        ),
        "paeoniaceae": Entry(
            commonName: "Peony Family",
            forageNote: "No nectar at all, and a great bowl of pollen. Bees roll in it.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.20, complete: 0.85, pollen: 1.8, nectar: false)
        ),
        "violaceae": Entry(
            commonName: "Violet Family",
            forageNote: "Pansies and violets hide a little nectar in a spur. Worked in passing, never in earnest.",
            traits: traits(corolla: 6, sugar: 0.35, volume: 0.2, protein: 0.18, complete: 0.85, pollen: 0.4)
        ),
        "begoniaceae": Entry(
            commonName: "Begonia Family",
            forageNote: "Bedding begonias are bred for colour and offer bees almost nothing.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.15, complete: 0.75, pollen: 0.3, nectar: false)
        ),
        "onagraceae": Entry(
            commonName: "Willowherb Family",
            forageNote: "Rosebay willowherb on cleared ground is one of the great honey plants. Fuchsia, its garden cousin, hangs its nectar too deep.",
            traits: traits(corolla: 6, sugar: 0.45, volume: 1.2, protein: 0.20, complete: 0.90, pollen: 0.8)
        ),
        "rubiaceae": Entry(
            commonName: "Bedstraw Family",
            forageNote: "Tiny open flowers in frothy masses. A little from each, and a lot of them.",
            traits: traits(corolla: 2, sugar: 0.30, volume: 0.3, protein: 0.17, complete: 0.80, pollen: 0.6)
        ),
        "magnoliaceae": Entry(
            commonName: "Magnolia Family",
            forageNote: "Older than bees: these flowers were made for beetles, and give pollen but no nectar.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.18, complete: 0.80, pollen: 1.0, nectar: false)
        ),
        "theaceae": Entry(
            commonName: "Tea Family",
            forageNote: "Camellias flower in the cold months and are worked for pollen and a little nectar whenever it is warm enough to fly.",
            traits: traits(corolla: 2, sugar: 0.30, volume: 0.8, protein: 0.20, complete: 0.85, pollen: 1.4)
        ),
        "convolvulaceae": Entry(
            commonName: "Bindweed Family",
            forageNote: "Wide funnels with the nectar at the bottom. Bindweed is worked; morning glory less so.",
            traits: traits(corolla: 10, sugar: 0.30, volume: 0.8, protein: 0.18, complete: 0.85, pollen: 0.7)
        ),
        "nymphaeaceae": Entry(
            commonName: "Water-lily Family",
            forageNote: "Pollen only, from a flower that closes by afternoon and sits over water.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.18, complete: 0.80, pollen: 1.0, nectar: false)
        ),
        "cactaceae": Entry(
            commonName: "Cactus Family",
            forageNote: "Enormous open cups, briefly, with nectar and pollen in quantity. A cactus flower in a pot is a good morning's work.",
            traits: traits(corolla: 3, sugar: 0.35, volume: 1.2, protein: 0.20, complete: 0.85, pollen: 1.8)
        ),
        "proteaceae": Entry(
            commonName: "Protea Family",
            forageNote: "Heavy, dilute nectar meant for birds. Bees take it where they can reach it.",
            traits: traits(corolla: 8, sugar: 0.30, volume: 2.5, protein: 0.15, complete: 0.70, pollen: 0.8)
        ),
        "caprifoliaceae": Entry(
            commonName: "Honeysuckle Family",
            forageNote: "Scabious and valerian are excellent and open; honeysuckle itself is a tube only a long tongue reaches.",
            traits: traits(corolla: 8, sugar: 0.40, volume: 0.8, protein: 0.19, complete: 0.85, pollen: 0.8)
        ),
        "primulaceae": Entry(
            commonName: "Primrose Family",
            forageNote: "Early, and welcome for it, but the nectar sits at the end of a tube most honey bees cannot manage.",
            traits: traits(corolla: 10, sugar: 0.35, volume: 0.3, protein: 0.18, complete: 0.85, pollen: 0.5)
        ),
        "campanulaceae": Entry(
            commonName: "Bellflower Family",
            forageNote: "Bells with good pollen and fair nectar, easy to climb into. Bumblebees sleep in them.",
            traits: traits(corolla: 8, sugar: 0.35, volume: 0.6, protein: 0.20, complete: 0.90, pollen: 1.0)
        ),
        "scrophulariaceae": Entry(
            commonName: "Figwort Family",
            forageNote: "Buddleja is a butterfly flower, its tubes too long for a honey bee. Figwort, oddly, is a wasp flower that bees will also work.",
            traits: traits(corolla: 9, sugar: 0.40, volume: 0.6, protein: 0.18, complete: 0.85, pollen: 0.5)
        ),
        "poaceae": Entry(
            commonName: "Grass Family",
            forageNote: "Wind-pollinated and nectarless. Maize pollen is gathered when there is nothing better, and it is poor stuff.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.15, complete: 0.70, pollen: 1.5, nectar: false)
        ),
        "euphorbiaceae": Entry(
            commonName: "Spurge Family",
            forageNote: "Nectar on open glands anyone can reach, in small amounts. Poinsettias are in here, and give nothing.",
            traits: traits(corolla: 0.5, sugar: 0.30, volume: 0.4, protein: 0.15, complete: 0.70, pollen: 0.8)
        ),
        "cucurbitaceae": Entry(
            commonName: "Gourd Family",
            forageNote: "Courgettes, pumpkins and cucumbers: huge open flowers full of nectar and pollen, each open for a single morning.",
            traits: traits(corolla: 4, sugar: 0.35, volume: 2.0, protein: 0.20, complete: 0.85, pollen: 1.5)
        ),
        "myrtaceae": Entry(
            commonName: "Myrtle Family",
            forageNote: "Eucalyptus and bottlebrush: bosses of stamens with nectar pooled at the base. The backbone of Australian honey.",
            traits: traits(corolla: 1, sugar: 0.40, volume: 2.0, protein: 0.18, complete: 0.80, pollen: 1.6)
        ),
        "rutaceae": Entry(
            commonName: "Citrus Family",
            forageNote: "Orange blossom. Open, fragrant, and generous with nectar for the few weeks it lasts.",
            traits: traits(corolla: 3, sugar: 0.35, volume: 1.5, protein: 0.20, complete: 0.85, pollen: 1.0)
        ),
        "sapindaceae": Entry(
            commonName: "Maple Family",
            forageNote: "Sycamore, field maple and horse chestnut: the big spring trees, with open nectar and heavy pollen when the colony is growing fastest.",
            traits: traits(corolla: 2, sugar: 0.35, volume: 1.0, protein: 0.20, complete: 0.85, pollen: 1.3)
        ),
        "polygonaceae": Entry(
            commonName: "Knotweed Family",
            forageNote: "Buckwheat makes a dark, strong honey. Japanese knotweed, whatever else is said of it, feeds bees in September.",
            traits: traits(corolla: 1, sugar: 0.40, volume: 0.8, protein: 0.18, complete: 0.80, pollen: 0.9)
        ),
        "hypericaceae": Entry(
            commonName: "St John's-wort Family",
            forageNote: "No nectar, and a great brush of stamens. Pollen only.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.18, complete: 0.80, pollen: 1.5, nectar: false)
        ),
        "lythraceae": Entry(
            commonName: "Loosestrife Family",
            forageNote: "Purple loosestrife on a river bank in August is a fine nectar plant, and worked hard.",
            traits: traits(corolla: 6, sugar: 0.40, volume: 0.8, protein: 0.18, complete: 0.85, pollen: 0.8)
        ),
        "gentianaceae": Entry(
            commonName: "Gentian Family",
            forageNote: "Deep trumpets for bumblebees. A honey bee looks in and leaves.",
            traits: traits(corolla: 20, sugar: 0.35, volume: 0.8, protein: 0.18, complete: 0.85, pollen: 0.4)
        ),
        "verbenaceae": Entry(
            commonName: "Verbena Family",
            forageNote: "Small tubes in flat heads, sized for butterflies. A little nectar for a bee that persists.",
            traits: traits(corolla: 8, sugar: 0.35, volume: 0.5, protein: 0.18, complete: 0.85, pollen: 0.5)
        ),
        "passifloraceae": Entry(
            commonName: "Passionflower Family",
            forageNote: "An open flower with a ring of nectar under the crown. Big bees are the intended guests, but everyone is served.",
            traits: traits(corolla: 3, sugar: 0.35, volume: 2.0, protein: 0.20, complete: 0.85, pollen: 1.2)
        ),
        "tropaeolaceae": Entry(
            commonName: "Nasturtium Family",
            forageNote: "The nectar is at the tip of a long spur. Bumblebees bite through; honey bees mostly go without.",
            traits: traits(corolla: 25, sugar: 0.40, volume: 1.5, protein: 0.18, complete: 0.85, pollen: 0.6)
        ),
        "cornaceae": Entry(
            commonName: "Dogwood Family",
            forageNote: "Small open flowers in flat heads, worked for both nectar and pollen in early summer.",
            traits: traits(corolla: 1, sugar: 0.30, volume: 0.5, protein: 0.18, complete: 0.85, pollen: 0.9)
        ),
        "aquifoliaceae": Entry(
            commonName: "Holly Family",
            forageNote: "Small, easily overlooked, and one of the better May nectar sources in a hedge.",
            traits: traits(corolla: 1, sugar: 0.40, volume: 0.6, protein: 0.18, complete: 0.85, pollen: 0.8)
        ),
        "vitaceae": Entry(
            commonName: "Grape Family",
            forageNote: "Tiny green flowers, open to anything. Virginia creeper on a wall hums in July.",
            traits: traits(corolla: 0.5, sugar: 0.35, volume: 0.5, protein: 0.18, complete: 0.85, pollen: 0.8)
        ),
        "cistaceae": Entry(
            commonName: "Rock-rose Family",
            forageNote: "Pollen only, in abundance, from flowers that last a single day.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.18, complete: 0.80, pollen: 1.8, nectar: false)
        ),
        "araceae": Entry(
            commonName: "Arum Family",
            forageNote: "Lords-and-ladies and peace lilies trap flies, not bees. Nothing here for the colony.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.12, complete: 0.60, pollen: 0.2, nectar: false)
        ),
        "arecaceae": Entry(
            commonName: "Palm Family",
            forageNote: "Sprays of thousands of tiny flowers. Pollen in quantity and some nectar, where palms grow.",
            traits: traits(corolla: 0.5, sugar: 0.30, volume: 0.4, protein: 0.15, complete: 0.75, pollen: 1.5)
        ),
        "zingiberaceae": Entry(
            commonName: "Ginger Family",
            forageNote: "Deep, elaborate flowers for birds and big bees. Out of a honey bee's reach.",
            traits: traits(corolla: 20, sugar: 0.30, volume: 1.0, protein: 0.18, complete: 0.80, pollen: 0.3)
        ),
        "nelumbonaceae": Entry(
            commonName: "Lotus Family",
            forageNote: "A great pollen flower and no nectar, held over open water.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.18, complete: 0.80, pollen: 1.2, nectar: false)
        ),
        "amaranthaceae": Entry(
            commonName: "Amaranth Family",
            forageNote: "Wind-pollinated for the most part. Pollen only, and not much sought.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.15, complete: 0.70, pollen: 1.0, nectar: false)
        ),
        "asphodelaceae": Entry(
            commonName: "Asphodel Family",
            forageNote: "Aloes and red-hot pokers: bird flowers dripping with thin nectar, which bees mop up at the mouth of the tube.",
            traits: traits(corolla: 15, sugar: 0.30, volume: 2.0, protein: 0.15, complete: 0.75, pollen: 0.6)
        ),
        "viburnaceae": Entry(
            commonName: "Elder Family",
            forageNote: "Elder and viburnum: flat heads of small open flowers, mostly worked for pollen.",
            traits: traits(corolla: 1, sugar: 0.30, volume: 0.4, protein: 0.18, complete: 0.85, pollen: 1.2)
        ),
        "adoxaceae": Entry(
            commonName: "Elder Family",
            forageNote: "Elder and viburnum: flat heads of small open flowers, mostly worked for pollen.",
            traits: traits(corolla: 1, sugar: 0.30, volume: 0.4, protein: 0.18, complete: 0.85, pollen: 1.2)
        ),
        "thymelaeaceae": Entry(
            commonName: "Daphne Family",
            forageNote: "Scented tubes in February. Worth something for when they open, not for what is in them.",
            traits: traits(corolla: 8, sugar: 0.35, volume: 0.5, protein: 0.17, complete: 0.80, pollen: 0.4)
        ),
        "acanthaceae": Entry(
            commonName: "Acanthus Family",
            forageNote: "Big hooded flowers with a deep throat, made for the largest bumblebees.",
            traits: traits(corolla: 20, sugar: 0.35, volume: 1.0, protein: 0.18, complete: 0.85, pollen: 0.5)
        ),
        "bignoniaceae": Entry(
            commonName: "Trumpet-vine Family",
            forageNote: "Trumpets the length of a finger, for hummingbirds. Bees rob them from the outside if they can.",
            traits: traits(corolla: 30, sugar: 0.30, volume: 3.0, protein: 0.15, complete: 0.75, pollen: 0.4)
        ),
        "apocynaceae": Entry(
            commonName: "Dogbane Family",
            forageNote: "Milkweeds are heavy nectar plants that trap the occasional bee by the foot. Periwinkles and oleander give little.",
            traits: traits(corolla: 8, sugar: 0.40, volume: 1.5, protein: 0.15, complete: 0.75, pollen: 0.4)
        ),
        "saxifragaceae": Entry(
            commonName: "Saxifrage Family",
            forageNote: "Small, open and early. Something in a rockery in April.",
            traits: traits(corolla: 1, sugar: 0.30, volume: 0.3, protein: 0.18, complete: 0.85, pollen: 0.7)
        ),
        "grossulariaceae": Entry(
            commonName: "Currant Family",
            forageNote: "Flowering currant and gooseberry: April nectar and pollen, worked hard on a fine day.",
            traits: traits(corolla: 3, sugar: 0.40, volume: 0.8, protein: 0.20, complete: 0.85, pollen: 0.9)
        ),
        "fagaceae": Entry(
            commonName: "Beech Family",
            forageNote: "Sweet chestnut in July is a major, bitter honey. Oak and beech give pollen and honeydew.",
            traits: traits(corolla: 0.5, sugar: 0.35, volume: 0.6, protein: 0.15, complete: 0.75, pollen: 1.5)
        ),
        "betulaceae": Entry(
            commonName: "Birch Family",
            forageNote: "Hazel catkins in February are the first pollen of the year, and no nectar with it.",
            traits: traits(corolla: 0, sugar: 0, volume: 0, protein: 0.15, complete: 0.70, pollen: 2.0, nectar: false)
        )
    ]
}
