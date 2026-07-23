// Detects chunk decodes where rapid zh/en code-switching (or overlapping voices) made the single
// greedy ASR pass interleave both languages into out-of-order word-salad, and arbitrates between
// the original and a fine-grained re-decode. Pure over display pieces so it is fully testable.
// The signature of interleave — as opposed to legitimate code-switching — is many script
// transitions with short "interruptions": isolated fragments of one script embedded in runs of
// the other (e.g. English function words scattered through a Mandarin clause).
import Foundation

enum CodeSwitchAnalyzer {
    /// Script alternation profile of a piece stream.
    struct Score: Equatable {
        /// Number of CJK↔Latin run boundaries.
        let transitions: Int
        /// Short runs (Latin ≤ 2 pieces, CJK ≤ 4 characters) sandwiched between runs of the
        /// opposite script — fragments that interrupt the other language mid-clause.
        let interruptions: Int
    }

    /// A chunk qualifies as interleaved when it alternates scripts often AND at least two of the
    /// runs are embedded fragments. One borrowed word inside a Mandarin sentence (`怎么说
    /// creators 嗯`) or a full English sentence between Mandarin clauses stays below both bars.
    static func isInterleaved(pieces: [String]) -> Bool {
        let score = score(pieces: pieces)
        return score.transitions >= 4 && score.interruptions >= 2
    }

    static func score(pieces: [String]) -> Score {
        // Collapse pieces into script runs; punctuation-only pieces are neutral and attach to
        // whichever run they follow (they carry no language evidence of their own).
        var runs: [(cjk: Bool, count: Int)] = []
        for piece in pieces {
            guard let cjk = script(of: piece) else { continue }
            if let last = runs.last, last.cjk == cjk {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((cjk, 1))
            }
        }
        guard runs.count > 1 else { return Score(transitions: 0, interruptions: 0) }

        var interruptions = 0
        for index in 1..<(runs.count - 1) {
            let run = runs[index]
            let short = run.cjk ? run.count <= 4 : run.count <= 2
            // Neighbors are by construction the opposite script (runs alternate).
            if short { interruptions += 1 }
        }
        return Score(transitions: runs.count - 1, interruptions: interruptions)
    }

    /// Arbitrates between the original decode and a fine-grained re-decode of the same audio.
    /// The re-decode is adopted only when it measurably reduces alternation — either it no longer
    /// qualifies as interleaved, or it strictly lowers transitions without adding interruptions.
    /// `stillInterleaved` reports whether the chosen text remains salad and must be flagged.
    static func preferred(
        original: [String], refined: [String]
    ) -> (useRefined: Bool, stillInterleaved: Bool) {
        guard !refined.isEmpty else { return (false, isInterleaved(pieces: original)) }
        let originalScore = score(pieces: original)
        let refinedScore = score(pieces: refined)
        let refinedClean = !(refinedScore.transitions >= 4 && refinedScore.interruptions >= 2)
        let refinedBetter = refinedClean
            || (refinedScore.transitions < originalScore.transitions
                && refinedScore.interruptions <= originalScore.interruptions)
        let chosen = refinedBetter ? refinedScore : originalScore
        return (refinedBetter, chosen.transitions >= 4 && chosen.interruptions >= 2)
    }

    /// true = CJK, false = Latin/alphanumeric, nil = punctuation-only (no language evidence).
    private static func script(of piece: String) -> Bool? {
        var sawAlphanumeric = false
        for scalar in piece.unicodeScalars {
            let value = Int(scalar.value)
            if (0x3000...0x303F).contains(value) { continue }  // CJK punctuation block
            if (0x2E80...0x9FFF).contains(value) || (0xF900...0xFAFF).contains(value) { return true }
            if CharacterSet.alphanumerics.contains(scalar) { sawAlphanumeric = true }
        }
        return sawAlphanumeric ? false : nil
    }
}
