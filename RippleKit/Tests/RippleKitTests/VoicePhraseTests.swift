import XCTest
@testable import RippleKit

final class VoicePhraseTests: XCTestCase {
    func testMatchesWhateverWayRecognitionWritesIt() {
        let phrase = "I am currently fine"
        XCTAssertTrue(VoicePhrase.matches("I am currently fine.", phrase: phrase))
        XCTAssertTrue(VoicePhrase.matches("I'm currently fine", phrase: phrase))
        XCTAssertTrue(VoicePhrase.matches("i’m CURRENTLY fine", phrase: phrase), "Curly apostrophe and capitals")
        XCTAssertTrue(VoicePhrase.matches("I'm OK", phrase: "I'm okay"))
        XCTAssertTrue(VoicePhrase.matches("I am okay", phrase: "I'm okay"))
    }

    func testMatchesInsideLongerSpeech() {
        XCTAssertTrue(VoicePhrase.matches("Oh sorry, I am currently fine, thanks", phrase: "I am currently fine"))
    }

    func testNeedsTheWholePhraseInOrder() {
        let phrase = "I am currently fine"
        XCTAssertFalse(VoicePhrase.matches("I am currently", phrase: phrase))
        XCTAssertFalse(VoicePhrase.matches("I am not currently fine", phrase: phrase))
        XCTAssertFalse(VoicePhrase.matches("I'm not okay", phrase: "I'm okay"))
        XCTAssertFalse(VoicePhrase.matches("Fine, I am currently", phrase: phrase))
    }

    func testWholeWordsOnly() {
        XCTAssertFalse(VoicePhrase.matches("Tim okay", phrase: "I'm okay"))
        XCTAssertFalse(VoicePhrase.matches("I am currently finest", phrase: "I am currently fine"))
    }

    func testEmptyPhraseNeverMatches() {
        XCTAssertFalse(VoicePhrase.matches("anything", phrase: ""))
        XCTAssertFalse(VoicePhrase.matches("anything", phrase: " ,. "))
    }
}
