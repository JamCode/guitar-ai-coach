import Foundation

public struct RhythmQuestionGenerator {

    /// 指定难度下可用的节奏型池
    public static func pool(for difficulty: RhythmDifficulty) -> [[Int]] {
        switch difficulty {
        case .beginner:
            return [
                [1,0,1,0,1,0,1,0],  // X X X X
                [1,1,1,1,1,1,1,1],  // XX XX XX XX
                [1,0,1,1,1,0,1,0],  // X XX X· X
                [1,1,1,0,1,1,1,0],  // XX X· XX X·
                [1,0,1,0,1,1,1,0],  // X X XX X·
                [1,1,1,0,1,0,1,0],  // XX X· X X
                [1,0,1,0,1,0,1,1],  // X X X XX
                [1,1,1,0,1,0,1,1],  // XX X· X XX
                [1,1,1,1,1,0,1,0],  // XX XX X· X
                [1,0,1,1,1,0,1,1],  // X XX X· XX
            ]
        case .intermediate:
            return [
                [1,0,0,0,1,0,1,0],  // X· . X X
                [1,0,1,0,0,0,1,0],  // X X . X
                [0,0,1,0,1,0,1,0],  // . X X X
                [0,0,1,1,1,0,1,0],  // . XX X· X
                [1,1,0,0,1,0,1,0],  // XX . X X
                [1,0,1,1,0,0,1,0],  // X XX . X
                [1,0,1,0,1,0,0,0],  // X X X .
                [1,1,1,0,0,0,1,0],  // XX X· . X
                [1,0,0,0,1,1,1,0],  // X· . XX X·
                [0,0,1,0,1,1,1,0],  // . X XX X·
            ]
        case .advanced:
            return [
                [1,0,0,0,0,0,1,0],  // X· . . X
                [0,0,1,0,0,0,1,1],  // . X . XX
                [1,1,0,0,0,0,1,0],  // XX . . X
                [1,0,1,0,0,0,0,0],  // X X . .
                [0,0,0,0,1,0,1,0],  // . . X X
                [1,0,0,0,1,0,0,0],  // X· . X· .
                [0,0,1,0,1,0,0,0],  // . X X· .
                [1,1,0,0,1,1,0,0],  // XX . XX .
                [0,0,0,0,0,0,1,1],  // . . . XX
                [1,1,1,1,0,0,0,0],  // XX XX . .
            ]
        }
    }

    /// 根据 pool 随机选一个正确节奏，生成 3 个干扰项，打乱后返回
    /// - Returns: (correct: 正确答案, choices: 4 个打乱后的选项)
    public static func makeQuestion(
        difficulty: RhythmDifficulty,
        using rng: inout some RandomNumberGenerator
    ) -> (correct: RhythmPattern, choices: [RhythmPattern]) {
        let pool = self.pool(for: difficulty)
        guard let correctGrid = pool.randomElement(using: &rng),
              let correct = RhythmPattern(grid: correctGrid) else {
            fatalError("Rhythm pool should not be empty")
        }

        // 从整池中选 3 个不同干扰项
        var distractors: [RhythmPattern] = []
        var candidates = pool.filter { $0 != correctGrid }
        candidates.shuffle(using: &rng)
        for grid in candidates {
            guard let p = RhythmPattern(grid: grid) else { continue }
            if !distractors.contains(p) {
                distractors.append(p)
                if distractors.count == 3 { break }
            }
        }

        // 如果池子太小不够 3 个不同，用变形补
        while distractors.count < 3 {
            guard let alt = makeDistractor(from: correctGrid, avoid: Set(distractors.map(\.grid)), using: &rng),
                  let p = RhythmPattern(grid: alt) else { break }
            distractors.append(p)
        }

        var choices = distractors + [correct]
        choices.shuffle(using: &rng)
        return (correct, choices)
    }

    /// 对正确节奏做一位翻转，生成干扰项
    private static func makeDistractor(
        from grid: [Int],
        avoid: Set<[Int]>,
        using rng: inout some RandomNumberGenerator
    ) -> [Int]? {
        for _ in 0..<20 {
            var copy = grid
            let idx = Int.random(in: 0..<8, using: &rng)
            copy[idx] = copy[idx] == 1 ? 0 : 1
            if copy != grid, !avoid.contains(copy) {
                return copy
            }
        }
        return nil
    }
}

// MARK: - [Int] Hashable conformance for avoid set

extension Array: @retroactive Hashable where Element == Int {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for v in self { hasher.combine(v) }
    }
}
