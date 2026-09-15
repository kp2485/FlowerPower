import Testing
@testable import FlowerPowerCore

/// The geometry the whole world stands on.
///
/// Every one of these is about an ordering or a partition rather than a
/// number, because that is what the rest of the game depends on: the garden is
/// planted in ring order, the map is drawn in ring order, and a cell that
/// belonged to two chunks — or to none — would be a hole in the countryside.
@Suite("Hex geometry")
struct HexTests {

    // MARK: - Distance

    @Test("A cell is no distance from itself")
    func originIsZeroFromItself() {
        #expect(HexCoordinate.origin.distance(to: .origin) == 0)
        #expect(HexCoordinate.origin.metres(to: .origin) == 0)
    }

    @Test("Every neighbour is one cell away, and 200 metres")
    func neighboursAreOneAway() {
        for neighbour in HexCoordinate.origin.neighbours {
            #expect(HexCoordinate.origin.distance(to: neighbour) == 1)
            #expect(neighbour.metresFromOrigin == HexCoordinate.cellMetres)
        }
    }

    @Test("There are six neighbours and they are all different")
    func sixDistinctNeighbours() {
        let neighbours = HexCoordinate(q: 4, r: -2).neighbours
        #expect(neighbours.count == 6)
        #expect(Set(neighbours).count == 6)
    }

    @Test("Distance is symmetric and obeys the triangle inequality")
    func distanceIsAMetric() {
        let a = HexCoordinate(q: 3, r: -5)
        let b = HexCoordinate(q: -2, r: 4)
        let c = HexCoordinate(q: 7, r: 1)

        #expect(a.distance(to: b) == b.distance(to: a))
        #expect(a.distance(to: c) <= a.distance(to: b) + b.distance(to: c))
    }

    @Test("Distance in metres is the hex count times the cell width")
    func metresFollowCells() {
        // The eight-kilometre foraging range is forty cells, which is the one
        // number in `WORLD.md` section 3 that the engine has to agree with.
        let edge = HexCoordinate(q: 40, r: 0)
        #expect(edge.distance(to: .origin) == 40)
        #expect(edge.metresFromOrigin == FlowerPatch.maximumForagingRange)
    }

    // MARK: - Rings

    @Test("Ring zero is the cell itself and a negative ring is empty")
    func degenerateRings() {
        #expect(HexCoordinate.origin.ring(radius: 0) == [HexCoordinate.origin])
        #expect(HexCoordinate.origin.ring(radius: -1).isEmpty)
    }

    @Test("A ring holds six cells per step out, all at that distance")
    func ringSizeAndDistance() {
        for radius in 1...6 {
            let ring = HexCoordinate.origin.ring(radius: radius)
            #expect(ring.count == 6 * radius)
            #expect(Set(ring).count == 6 * radius)
            #expect(ring.allSatisfy { $0.distance(to: .origin) == radius })
        }
    }

    @Test("The first ring starts due east and runs clockwise")
    func ringOrderIsFixed() {
        // Written out rather than derived. This is the order the garden is
        // planted in, so a change here moves every flower a player has put in
        // the ground and must fail a test rather than pass quietly.
        #expect(HexCoordinate.origin.ring(radius: 1) == [
            HexCoordinate(q: 1, r: 0),
            HexCoordinate(q: 0, r: 1),
            HexCoordinate(q: -1, r: 1),
            HexCoordinate(q: -1, r: 0),
            HexCoordinate(q: 0, r: -1),
            HexCoordinate(q: 1, r: -1)
        ])
    }

    @Test("Each step around a ring is to a neighbouring cell")
    func ringIsAWalk() {
        let ring = HexCoordinate.origin.ring(radius: 4)
        for index in ring.indices {
            let next = ring[(index + 1) % ring.count]
            #expect(ring[index].distance(to: next) == 1, "the ring walk jumped")
        }
    }

    @Test("Cells within a radius are every ring up to it, innermost first")
    func spiralOrder() {
        let cells = HexCoordinate.origin.cells(withinRadius: 3)
        #expect(cells.count == 37)
        #expect(Set(cells).count == 37)
        #expect(cells.first == .origin)
        // Non-decreasing distance: the garden opens outward, never inward.
        let distances = cells.map { $0.distance(to: .origin) }
        #expect(distances == distances.sorted())
    }

    // MARK: - Order

    @Test("The total order is by row and then by column")
    func comparableIsTotal() {
        #expect(HexCoordinate(q: 5, r: 0) < HexCoordinate(q: -5, r: 1))
        #expect(HexCoordinate(q: 1, r: 2) < HexCoordinate(q: 2, r: 2))
        #expect(!(HexCoordinate(q: 1, r: 1) < HexCoordinate(q: 1, r: 1)))

        // Sorting a set is the escape hatch from `Hasher` order, so it has to
        // actually produce one answer.
        let cells = HexCoordinate.origin.cells(withinRadius: 2)
        #expect(Set(cells).sorted() == Set(cells.reversed()).sorted())
    }

    // MARK: - Chunks

    @Test("A chunk is 37 cells, three deep around its centre")
    func chunkShape() {
        #expect(ChunkCoordinate.cellCount == 37)
        let chunk = ChunkCoordinate(q: 2, r: -1)
        let cells = chunk.cells
        #expect(cells.count == 37)
        #expect(Set(cells).count == 37)
        #expect(cells.first == chunk.centre)
        #expect(cells.allSatisfy { $0.distance(to: chunk.centre) <= ChunkCoordinate.radius })
    }

    @Test("The home chunk's centre is the nest")
    func homeChunkIsCentredOnTheNest() {
        #expect(ChunkCoordinate.origin.centre == .origin)
        #expect(ChunkCoordinate.containing(.origin) == .origin)
    }

    @Test("Every cell belongs to exactly one chunk")
    func chunksTileThePlane() {
        // A patch of country big enough to hold several chunks whole and to
        // cross the lattice in every direction, walked cell by cell.
        var claimed: [HexCoordinate: ChunkCoordinate] = [:]

        for q in -24...24 {
            for r in -24...24 {
                let cell = HexCoordinate(q: q, r: r)
                let chunk = ChunkCoordinate.containing(cell)

                #expect(chunk.contains(cell), "\(cell) was given a chunk it is not in")
                #expect(claimed[cell] == nil)
                claimed[cell] = chunk
            }
        }

        // And from the other direction: a chunk's own cell list agrees with
        // the lookup, which is what rules out a cell belonging to two.
        for q in -3...3 {
            for r in -3...3 {
                let chunk = ChunkCoordinate(q: q, r: r)
                for cell in chunk.cells {
                    #expect(ChunkCoordinate.containing(cell) == chunk,
                            "\(cell) is in \(chunk)'s list but looks up elsewhere")
                }
            }
        }
    }

    @Test("Chunk space is itself a hex grid")
    func chunkNeighboursAreAdjacent() {
        let chunk = ChunkCoordinate(q: 1, r: -2)
        let neighbours = chunk.neighbours

        #expect(neighbours.count == 6)
        #expect(Set(neighbours).count == 6)
        for neighbour in neighbours {
            #expect(chunk.distance(to: neighbour) == 1)
            // Adjacent chunks sit 2r + 1 cells apart, which is what makes the
            // radius-r hexagons meet without overlapping.
            #expect(chunk.centre.distance(to: neighbour.centre)
                    == 2 * ChunkCoordinate.radius + 1)
        }
    }

    @Test("Chunks of neighbouring cells are the same or adjacent")
    func chunkLookupIsContinuous() {
        for q in -12...12 {
            for r in -12...12 {
                let cell = HexCoordinate(q: q, r: r)
                let chunk = ChunkCoordinate.containing(cell)
                for neighbour in cell.neighbours {
                    let other = ChunkCoordinate.containing(neighbour)
                    #expect(chunk.distance(to: other) <= 1,
                            "\(cell) and \(neighbour) landed in chunks \(chunk) and \(other)")
                }
            }
        }
    }
}
