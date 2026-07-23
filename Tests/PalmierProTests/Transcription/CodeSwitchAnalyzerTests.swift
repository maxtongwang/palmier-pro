import Foundation
import Testing
@testable import PalmierPro

@Suite("Code-switch interleave detection")
struct CodeSwitchAnalyzerTests {
    // Piece streams mirror the real failure shapes (single-pass decode interleaving zh/en at
    // rapid switches) with synthetic vocabulary; CJK pieces are per-character as splitPieces emits.

    @Test func flagsIsolatedFunctionWordsScatteredThroughCJK() {
        // "going 我们在这里 out. 然后呢 how 走" — English function words strewn between CJK runs.
        let pieces = ["going", "我", "们", "在", "这", "里", "out.", "然", "后", "呢", "how", "走"]
        #expect(CodeSwitchAnalyzer.isInterleaved(pieces: pieces))
    }

    @Test func flagsEnglishPhraseSplitByCJKFragment() {
        // "…了 This is my 这是哪个 favorite. 颜色" — an English phrase torn apart by a short CJK run.
        let pieces = ["他", "们", "早", "就", "想", "去", "那", "里", "了",
                      "This", "is", "my", "这", "是", "哪", "个", "favorite.", "颜", "色"]
        #expect(CodeSwitchAnalyzer.isInterleaved(pieces: pieces))
    }

    @Test func flagsDenseAlternation() {
        let pieces = ["是", "跟", "我", "out.", "人", "们", "是", "how", "我", "们",
                      "to", "我", "们", "come", "是", "我", "们", "up", "然", "后"]
        #expect(CodeSwitchAnalyzer.isInterleaved(pieces: pieces))
    }

    @Test func passesBorrowedNounInsideCJKSentence() {
        // "博主怎么说 creators 嗯" — a legitimate single borrowed word must never flag.
        let pieces = ["博", "主", "怎", "么", "说", "creators", "嗯"]
        #expect(!CodeSwitchAnalyzer.isInterleaved(pieces: pieces))
    }

    @Test func passesFullSentenceSwitch() {
        // A complete English sentence between two Mandarin clauses is normal code-switching.
        let pieces = ["他", "说", "得", "很", "好", "That", "was", "really", "well", "said", "对", "不", "对", "呀"]
        #expect(!CodeSwitchAnalyzer.isInterleaved(pieces: pieces))
    }

    @Test func passesMonolingualStreams() {
        #expect(!CodeSwitchAnalyzer.isInterleaved(pieces: ["我", "们", "今", "天", "去", "哪", "里"]))
        #expect(!CodeSwitchAnalyzer.isInterleaved(pieces: ["we", "should", "figure", "this", "out", "today"]))
        #expect(!CodeSwitchAnalyzer.isInterleaved(pieces: []))
    }

    @Test func punctuationPiecesCarryNoLanguageEvidence() {
        // Marks between runs must not split or create runs.
        let pieces = ["你", "好", "。", "hello", "there", "，", "再", "见"]
        let score = CodeSwitchAnalyzer.score(pieces: pieces)
        #expect(score.transitions == 2)
        #expect(!CodeSwitchAnalyzer.isInterleaved(pieces: pieces))
    }

    @Test func preferredAdoptsCleanRefinedDecode() {
        let salad = ["going", "我", "们", "在", "这", "里", "out.", "然", "后", "呢", "how", "走"]
        let clean = ["going", "out.", "how", "我", "们", "在", "这", "里", "然", "后", "呢", "走"]
        let choice = CodeSwitchAnalyzer.preferred(original: salad, refined: clean)
        #expect(choice.useRefined)
        #expect(!choice.stillInterleaved)
    }

    @Test func preferredKeepsOriginalWhenRefinedIsEmpty() {
        let salad = ["going", "我", "们", "在", "这", "里", "out.", "然", "后", "呢", "how", "走"]
        let choice = CodeSwitchAnalyzer.preferred(original: salad, refined: [])
        #expect(!choice.useRefined)
        #expect(choice.stillInterleaved)
    }

    @Test func preferredKeepsOriginalWhenRefinedIsNoBetter() {
        let salad = ["going", "我", "们", "在", "这", "里", "out.", "然", "后", "呢", "how", "走"]
        let choice = CodeSwitchAnalyzer.preferred(original: salad, refined: salad)
        #expect(!choice.useRefined)
        #expect(choice.stillInterleaved)
    }

    @Test func preferredAdoptsStrictlyLowerAlternationEvenIfStillFlagged() {
        // Refined still qualifies as interleaved but alternates less — adopt AND keep the flag.
        let salad = ["是", "跟", "我", "out.", "人", "们", "是", "how", "我", "们",
                     "to", "我", "们", "come", "是", "我", "们", "up", "然", "后"]
        let lessSalad = ["是", "跟", "我", "们", "out.", "人", "们", "是", "我", "们",
                         "how", "我", "们", "come", "是", "然", "后", "up"]
        let choice = CodeSwitchAnalyzer.preferred(original: salad, refined: lessSalad)
        #expect(choice.useRefined)
        #expect(choice.stillInterleaved)
    }

    @Test func wordCodeSwitchFlagDecodesAsNilFromOlderCachedJSON() throws {
        // Transcripts cached before the flag existed must decode with codeSwitch == nil.
        let old = #"{"text":"你好","start":1.0,"end":2.0}"#.data(using: .utf8)!
        let word = try JSONDecoder().decode(TranscriptionWord.self, from: old)
        #expect(word.codeSwitch == nil)

        let flagged = TranscriptionWord(text: "hi", start: 0, end: 1, codeSwitch: true)
        let roundTrip = try JSONDecoder().decode(
            TranscriptionWord.self, from: JSONEncoder().encode(flagged))
        #expect(roundTrip.codeSwitch == true)
    }
}
