import XCTest

final class VisualTests: XCTestCase {
    @MainActor private func launch(onboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboardingSchemaVersion", onboarding ? "0" : "3",
            "-appLanguage", "ru", "-preferredBookLanguage", "ru",
            "-hintLibraryShown", "YES", "-hintCatalogShown", "YES", "-hintReaderShown", "YES"
        ]
        app.launch()
        return app
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testEmptyAudioLibraryAndSources() {
        let app = launch()
        XCTAssertTrue(app.buttons["Аудиокниги"].waitForExistence(timeout:10))
        app.buttons["Аудиокниги"].tap()
        XCTAssertTrue(app.staticTexts["Время слушать"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Импортировать аудиокнигу"].exists)
        capture("01-audio-library", app)

        app.tabBars.buttons["Каталог"].tap()
        app.buttons["Аудиокниги"].tap()
        let sources = app.buttons["audio-source-menu"]
        XCTAssertTrue(sources.waitForExistence(timeout:10))
        sources.tap()
        app.buttons["Управление источниками"].tap()
        XCTAssertTrue(app.switches["audio-source-librivox"].firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.switches["audio-source-archive"].firstMatch.exists)
        capture("02-audio-sources", app)

        app.tabBars.buttons["Поиск"].tap()
        app.buttons["Аудиокниги"].tap()
        XCTAssertTrue(app.buttons["Русский"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["English"].exists)
        XCTAssertTrue(app.buttons["Все"].exists)
        XCTAssertFalse(app.buttons["Автоматически"].exists)
        capture("03-audio-search", app)
    }

    @MainActor func testRussianOnboardingAndBookSelection() {
        let app = launch(onboarding:true)
        XCTAssertTrue(app.staticTexts["Выберите язык"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts.matching(identifier:"Язык можно изменить в настройках.").count,1)
        capture("04-language", app)
        app.buttons["Продолжить"].tap()
        app.buttons["Продолжить"].tap()
        let genre = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Приключения")).firstMatch
        XCTAssertTrue(genre.waitForExistence(timeout:5))
        genre.tap()
        app.buttons["Продолжить"].tap()
        XCTAssertTrue(app.staticTexts["Выберите книги"].waitForExistence(timeout:5))
        let book = app.scrollViews.buttons.matching(NSPredicate(format:"label != %@", "Повторить")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:40),"Russian discovery must return an actual selectable book")
        book.tap()
        capture("05-russian-books", app)
    }
}
