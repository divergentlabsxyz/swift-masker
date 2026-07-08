import Testing
@testable import Masker

@Suite("Chunker — fixed-width windows with overlap")
struct ChunkerTests {

    private func tokens(_ n: Int) -> [EncodedToken] {
        (0..<n).map { EncodedToken(id: $0, range: nil) }
    }

    @Test("Short sequences produce a single window")
    func single() {
        let chunker = Chunker(maxLength: 8, overlap: 2)   // capacity 6
        #expect(chunker.windows(tokens(6)).count == 1)
        #expect(chunker.windows(tokens(3)).count == 1)
        #expect(chunker.windows([]).isEmpty)
    }

    @Test("Long sequences split into overlapping windows")
    func overlapping() {
        let chunker = Chunker(maxLength: 8, overlap: 2)   // capacity 6, stride 4
        let windows = chunker.windows(tokens(10))
        #expect(windows.count == 2)
        #expect(windows[0].map(\.id) == [0, 1, 2, 3, 4, 5])
        #expect(windows[1].map(\.id) == [4, 5, 6, 7, 8, 9])   // shares 4,5
    }

    @Test("Coverage is complete — every token appears in some window")
    func coverage() {
        let chunker = Chunker(maxLength: 10, overlap: 3)
        let n = 25
        let windows = chunker.windows(tokens(n))
        let covered = Set(windows.flatMap { $0.map(\.id) })
        #expect(covered == Set(0..<n))
    }

    @Test("Overlap is clamped so windows always advance")
    func clampedOverlap() {
        let chunker = Chunker(maxLength: 5, overlap: 100)  // absurd overlap
        let windows = chunker.windows(tokens(20))
        #expect(windows.count > 1)                          // still terminates & advances
        #expect(windows.allSatisfy { !$0.isEmpty })
    }
}
