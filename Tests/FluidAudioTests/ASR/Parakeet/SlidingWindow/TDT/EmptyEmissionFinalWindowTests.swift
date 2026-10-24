import XCTest
@testable import FluidAudio

final class EmptyEmissionFinalWindowTests: XCTestCase {
    func testFinalEmptyEmissionReDecodeStartsFreshWithoutCutoff() {
        let plan = AsrManager.redecodePlan(
            redecode: true, previousTokens: [], previousTokenTimestamps: [], globalFrameOffset: 0)
        XCTAssertEqual(
            plan.initialTimeIndexOverride, 0,
            "A blank early window can still advance decoder navigation; EOF must re-decode the retained audio.")
        XCTAssertNil(plan.emitTokensAfterFrame, "No previously emitted tokens means no prefix to suppress.")
    }
    func testFinalEmptyEmissionWithoutTimestampArrayAlsoStartsFresh() {
        let plan = AsrManager.redecodePlan(
            redecode: true, previousTokens: [], previousTokenTimestamps: nil, globalFrameOffset: 20)
        XCTAssertEqual(plan.initialTimeIndexOverride, 0)
        XCTAssertNil(plan.emitTokensAfterFrame)
    }
    func testFirstWindowRetainsNormalNavigation() {
        let plan = AsrManager.redecodePlan(
            redecode: false, previousTokens: [], previousTokenTimestamps: [], globalFrameOffset: 0)
        XCTAssertNil(plan.initialTimeIndexOverride)
        XCTAssertNil(plan.emitTokensAfterFrame)
    }
    func testExistingOutputRetainsItsSuppressionBoundary() {
        let plan = AsrManager.redecodePlan(
            redecode: true, previousTokens: [10, 11], previousTokenTimestamps: [20, 30], globalFrameOffset: 10,
            lastWordStartFrame: 30)
        XCTAssertEqual(plan.initialTimeIndexOverride, 0)
        XCTAssertEqual(plan.emitTokensAfterFrame, 15)
    }
    func testMissingTimingsForExistingTokensKeepsLegacyFallback() {
        let plan = AsrManager.redecodePlan(
            redecode: true, previousTokens: [10], previousTokenTimestamps: nil, globalFrameOffset: 0)
        XCTAssertNil(plan.initialTimeIndexOverride)
        XCTAssertNil(plan.emitTokensAfterFrame)
    }
}
