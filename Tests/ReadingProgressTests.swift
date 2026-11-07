import XCTest
@testable import DarkReader

final class ReadingProgressTests:XCTestCase {
    func testDefaultIsPercentAndUnknownOldPreferenceFallsBack() {
        XCTAssertEqual(ReadingProgressDisplay.stored(nil),.percent)
        XCTAssertEqual(ReadingProgressDisplay.stored(""),.percent)
        XCTAssertEqual(ReadingProgressDisplay.stored("pages"),.pages)
    }
    func testPercentUsesWholeBookProgressAndClampsWithoutInventingValues() {
        XCTAssertEqual(ReadingProgressDisplay.percent.text(fraction:0.666,position:12,total:30),"67%")
        XCTAssertEqual(ReadingProgressDisplay.percent.text(fraction:1,position:30,total:30),"100%")
        XCTAssertEqual(ReadingProgressDisplay.percent.text(fraction:nil,position:nil,total:nil),"—")
        XCTAssertEqual(ReadingProgressDisplay.percent.text(fraction:.nan,position:1,total:30),"—")
    }
    func testPageModeDisplaysActualPositionAndTotal() {
        XCTAssertEqual(ReadingProgressDisplay.pages.text(fraction:0.4,position:12,total:30),"Стр. 12 из 30")
        XCTAssertEqual(ReadingProgressDisplay.pages.text(fraction:nil,position:12,total:30,language:"en"),"Page 12 of 30")
        XCTAssertEqual(ReadingProgressDisplay.pages.text(fraction:nil,position:nil,total:nil),"—")
    }
}
