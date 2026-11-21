import Foundation

struct FuzzyMatchResult {
    let score: Int
    let matchedIndices: Set<Int>
}

enum FuzzyMatcher {
    /// Returns a score and matched character indices (0-based in `text`) if `query` matches `text`.
    /// Supports both direct substring match (highest score) and subsequence fuzzy match.
    static func match(query: String, in text: String) -> FuzzyMatchResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FuzzyMatchResult(score: 0, matchedIndices: [])
        }

        let queryChars = Array(trimmed.lowercased())
        let textChars = Array(text.lowercased())

        if queryChars.count > textChars.count {
            return nil
        }

        // Fast path: exact substring match
        if let range = text.lowercased().range(of: trimmed.lowercased()) {
            let startOffset = text.lowercased().distance(from: text.lowercased().startIndex, to: range.lowerBound)
            let length = queryChars.count
            var indices = Set<Int>()
            for i in startOffset..<(startOffset + length) {
                indices.insert(i)
            }
            var score = 1000 - startOffset * 3
            if startOffset == 0 {
                score += 200
            }
            return FuzzyMatchResult(score: score, matchedIndices: indices)
        }

        // Subsequence fuzzy matching with word-boundary bonuses
        var qIdx = 0
        var matched = Set<Int>()
        var score = 0
        var lastMatchIndex = -2

        for tIdx in 0..<textChars.count {
            if qIdx < queryChars.count && textChars[tIdx] == queryChars[qIdx] {
                matched.insert(tIdx)
                score += 20
                if tIdx == lastMatchIndex + 1 {
                    score += 35 // consecutive characters
                }
                if tIdx == 0 || textChars[tIdx - 1] == " " || textChars[tIdx - 1] == "-" || textChars[tIdx - 1] == "_" {
                    score += 40 // word boundary
                }
                lastMatchIndex = tIdx
                qIdx += 1
            }
        }

        guard qIdx == queryChars.count else { return nil }
        score -= (textChars.count - queryChars.count)
        return FuzzyMatchResult(score: max(1, score), matchedIndices: matched)
    }
}
