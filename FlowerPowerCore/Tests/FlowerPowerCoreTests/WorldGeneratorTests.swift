import Testing
@testable import FlowerPowerCore

/// The countryside.
///
/// Nothing the generator makes is stored, so every one of these is really the
/// same test: the same seed and coordinate must give the same answer, in any
/// order, in any process, on any platform. The literal expectations below are
/// the part that matters — a change to the hash that looks harmless moves
/// every player's map, and it must fail here rather than in somebody's save.
@Suite("World generation")
struct WorldGeneratorTests {

    // MARK: - Determinism

    @Test("The same seed and coordinate give the same chunk every time")
    func chunksAreStable() {
        let generator = WorldGenerator(seed: 1_234)
        let coordinate = ChunkCoordinate(q: 2, r: -3)

        let first = generator.chunk(at: coordinate)
        for _ in 0..<50 {
            #expect(generator.chunk(at: coordinate) == first)
        }
        #expect(WorldGenerator(seed: 1_234).chunk(at: coordinate) == first)
    }

    @Test("Different seeds give different country")
    func seedsDiverge() {
        let coordinates = ChunkCoordinate.origin.neighbours + [.origin]
        let one = coordinates.map { WorldGenerator(seed: 1).chunk(at: $0) }
        let two = coordinates.map { WorldGenerator(seed: 2).chunk(at: $0) }
        #expect(one != two, "the seed is not actually driving anything")
    }

    @Test("Chunks do not depend on the order they are asked for")
    func orderDoesNotMatter() {
        let generator = WorldGenerator(seed: 99)
        let coordinates = (-4...4).flatMap { q in (-4...4).map { ChunkCoordinate(q: q, r: $0) } }

        let forwards = coordinates.map(generator.chunk(at:))
        let backwards = coordinates.reversed().map(generator.chunk(at:)).reversed()
        #expect(Array(backwards) == forwards)
    }

    // MARK: - The fields

    @Test("Every field stays inside 0...1")
    func fieldsAreBounded() {
        let generator = WorldGenerator(seed: 5)
        for q in -20...20 {
            for r in -20...20 {
                let chunk = ChunkCoordinate(q: q, r: r)
                for value in [
                    generator.wetness(at: chunk),
                    generator.openness(at: chunk),
                    generator.settlement(at: chunk)
                ] {
                    #expect(value >= 0 && value <= 1)
                }
            }
        }
    }

    @Test("The fields vary slowly, so a biome is a region rather than a speckle")
    func fieldsAreSmooth() {
        let generator = WorldGenerator(seed: 17)
        var biggestStep = 0.0

        for q in -12...12 {
            for r in -12...12 {
                let chunk = ChunkCoordinate(q: q, r: r)
                let here = generator.wetness(at: chunk)
                for neighbour in chunk.neighbours {
                    biggestStep = max(biggestStep, abs(here - generator.wetness(at: neighbour)))
                }
            }
        }

        // One chunk of a four-chunk feature can move a field by at most a
        // quarter of its range plus the smoothstep's overshoot, which is
        // nothing. A hash sampled per chunk rather than interpolated would
        // step by close to 1 here and fail.
        #expect(biggestStep < 0.5, "the noise is not smooth; it is a speckle")
    }

    @Test("The three fields are independent of one another")
    func fieldsAreNotTheSameField() {
        let generator = WorldGenerator(seed: 3)
        let chunks = (-8...8).flatMap { q in (-8...8).map { ChunkCoordinate(q: q, r: $0) } }
        #expect(chunks.map(generator.wetness(at:)) != chunks.map(generator.openness(at:)))
        #expect(chunks.map(generator.wetness(at:)) != chunks.map(generator.settlement(at:)))
        #expect(chunks.map(generator.openness(at:)) != chunks.map(generator.settlement(at:)))
    }

    // MARK: - Biomes

    @Test("A stretch of country holds every kind of ground")
    func allSevenBiomesAppear() {
        // A hundred-odd chunks is about what a colony's range circle holds, so
        // this is the question "does one player's world have variety in it"
        // rather than a statistical claim about the generator.
        let generator = WorldGenerator(seed: 2_026)
        var found: Set<Biome> = []
        for q in -20...20 {
            for r in -20...20 {
                found.insert(generator.biome(at: ChunkCoordinate(q: q, r: r)))
            }
        }
        #expect(found.count == Biome.allCases.count,
                "missing: \(Biome.allCases.filter { !found.contains($0) })")
    }

    @Test("Every biome says something, and every flower in it is real")
    func biomesAreComplete() {
        for biome in Biome.allCases {
            #expect(!biome.displayName.isEmpty)
            #expect(!biome.summary.isEmpty)
            #expect(!biome.species.isEmpty)
            #expect(!WorldGenerator.nouns(for: biome).isEmpty)

            for id in biome.species {
                #expect(
                    FlowerCatalogue.species(withID: id) != nil,
                    "\(biome.rawValue) lists '\(id)', which is not in the catalogue"
                )
            }
            #expect(biome.flowers.count == biome.species.count)
        }
    }

    @Test("The village is the only ground with winter forage")
    func onlyTheVillageFlowersInWinter() {
        // Not a rule the generator enforces — it is what the catalogue says,
        // and `WORLD.md` section 4 leans the whole village biome on it. If the
        // catalogue ever changes, the design should hear about it here.
        for biome in Biome.allCases {
            let winter = biome.flowers.filter { $0.isInBloom(during: .winter) }
            if biome == .village {
                #expect(!winter.isEmpty)
            } else {
                #expect(winter.isEmpty, "\(biome.rawValue) has \(winter.map(\.commonName)) in winter")
            }
        }
    }

    // MARK: - Names

    @Test("Every chunk is called something, and a village is called something else")
    func namesAreWellFormed() {
        let generator = WorldGenerator(seed: 808)
        for q in -10...10 {
            for r in -10...10 {
                let chunk = generator.chunk(at: ChunkCoordinate(q: q, r: r))
                #expect(!chunk.name.isEmpty)
                #expect(chunk.name.first != " ")
                if chunk.biome == .village {
                    #expect(chunk.name.hasPrefix("the "))
                    #expect(chunk.name.contains(" at "))
                } else {
                    #expect(chunk.name.split(separator: " ").count >= 2)
                }
            }
        }
    }

    @Test("Neighbouring chunks are not all called the same thing")
    func namesVary() {
        let generator = WorldGenerator(seed: 31)
        let names = Set(
            (-6...6).flatMap { q in
                (-6...6).map { generator.chunk(at: ChunkCoordinate(q: q, r: $0)).name }
            }
        )
        #expect(names.count > 20)
    }

    // MARK: - Literals

    /// The values that pin the hash down.
    ///
    /// Written out rather than derived, on purpose, and they are allowed to
    /// change only when somebody means to change everybody's map. Every one of
    /// these was taken from a run of this same code — that is the only way to
    /// produce them — so the test is not that the numbers are *right* but that
    /// they are *fixed*.
    @Test("Chunks match their recorded values for a fixed seed")
    func literalChunks() {
        let generator = WorldGenerator(seed: 2_026)

        let expected: [(ChunkCoordinate, Biome, String)] = Self.recorded
        for (coordinate, biome, name) in expected {
            let chunk = generator.chunk(at: coordinate)
            #expect(chunk.biome == biome, "\(coordinate) is now \(chunk.biome.rawValue)")
            #expect(chunk.name == name, "\(coordinate) is now '\(chunk.name)'")
        }
    }

    /// Seed 2026's home chunk, its six neighbours, and two further out.
    ///
    /// Wet, wooded country with a village a couple of chunks over — which is
    /// the sort of thing a player gets, and it is here because it is what this
    /// code produced on the day it was written.
    static let recorded: [(ChunkCoordinate, Biome, String)] = [
        (ChunkCoordinate(q: 0, r: 0), .riverbank, "Mill Carr"),
        (ChunkCoordinate(q: 1, r: 0), .riverbank, "Nether Carr"),
        (ChunkCoordinate(q: 0, r: 1), .riverbank, "Stony Reach"),
        (ChunkCoordinate(q: -1, r: 1), .riverbank, "Old Ford"),
        (ChunkCoordinate(q: -1, r: 0), .riverbank, "Black Carr"),
        (ChunkCoordinate(q: 0, r: -1), .riverbank, "Upper Reach"),
        (ChunkCoordinate(q: 1, r: -1), .village, "the Gardens at Thornbury"),
        (ChunkCoordinate(q: 3, r: -2), .village, "the Lime Walk at Belchworth"),
        (ChunkCoordinate(q: -4, r: 5), .village, "the Green at Oakley")
    ]

    @Test("The hash and the fields under it are pinned")
    func literalHash() {
        // One value from each layer: the hash, and a field read through the
        // interpolation that sits on top of it. A change to either moves every
        // map ever generated, and this is the tripwire.
        #expect(WorldGenerator.hash(seed: 2_026, salt: 1, q: 3, r: -2)
                == 17_773_582_766_853_466_382)

        let generator = WorldGenerator(seed: 2_026)
        #expect(abs(generator.wetness(at: .origin) - 0.857_854_223_011_218_2) < 1e-15)
        #expect(abs(generator.openness(at: .origin) - 0.471_627_383_941_457_1) < 1e-15)
        #expect(abs(generator.settlement(at: .origin) - 0.667_344_955_216_218) < 1e-15)
    }
}
