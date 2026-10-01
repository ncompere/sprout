import XCTest

final class SproutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(style: String = "Light", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
                               style == "Dark" ? "--uitest-dark" : "--uitest-light"]
        if largeText {
            app.launchArguments += ["--uitest-large-text", "-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPlantLifecycleAndCalendar() throws {
        let app = launch()
        let name = "Monstera test \(UUID().uuidString.prefix(6))"
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 10))
        capture("Mes plantes — clair", app: app)
        app.buttons["plants.add"].tap()
        XCTAssertFalse(app.buttons["editor.save"].isEnabled)
        app.textFields["editor.name"].tap()
        app.textFields["editor.name"].typeText(name)
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        capture("Plante ajoutée", app: app)
        app.staticTexts[name].tap()
        XCTAssertTrue(app.buttons["plant.water"].waitForExistence(timeout: 5))
        app.buttons["plant.water"].tap()
        XCTAssertFalse(app.buttons["plant.water"].isEnabled)
        XCTAssertTrue(app.buttons["Arrosée aujourd’hui"].exists)
        capture("Arrosage enregistré", app: app)
        app.buttons["plant.edit"].tap()
        let interval = app.textFields["editor.interval"]
        XCTAssertTrue(interval.waitForExistence(timeout: 5))
        interval.tap()
        interval.typeText(XCUIKeyboardKey.delete.rawValue + "0")
        XCTAssertFalse(app.buttons["editor.save"].isEnabled)
        interval.typeText(XCUIKeyboardKey.delete.rawValue + "3")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["Tous les 3 jours"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
        app.tabBars.buttons["Calendrier"].tap()
        XCTAssertTrue(app.buttons["calendar.next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Arrosage effectué"].exists)
        capture("Calendrier — clair", app: app)
        let calendar = Calendar(identifier: .gregorian)
        let due = calendar.date(byAdding: .day, value: 3, to: Date.now)!
        if !calendar.isDate(due, equalTo: .now, toGranularity: .month) {
            app.buttons["calendar.next"].tap()
        }
        app.buttons["calendar.day.\(calendar.component(.day, from: due))"].tap()
        XCTAssertTrue(app.staticTexts["Arrosage prévu"].exists)
        app.buttons["calendar.today"].tap()
        let oldMonth = app.staticTexts["calendar.month"].label
        app.buttons["calendar.next"].tap()
        XCTAssertNotEqual(app.staticTexts["calendar.month"].label, oldMonth)
        app.buttons["calendar.previous"].tap()
        XCTAssertEqual(app.staticTexts["calendar.month"].label, oldMonth)
        app.buttons["calendar.today"].tap()
        app.tabBars.buttons["Mes plantes"].tap()
        app.staticTexts[name].tap()
        XCTAssertFalse(app.buttons["plant.water"].isEnabled)
        app.buttons["plant.delete"].tap()
        app.buttons["Supprimer"].tap()
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[name].exists)
    }

    func testDarkCalendarAndEmptyState() {
        let app = launch(style: "Dark")
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 10))
        capture("Mes plantes — sombre", app: app)
        app.tabBars.buttons["Calendrier"].tap()
        XCTAssertTrue(app.buttons["calendar.today"].waitForExistence(timeout: 5))
        capture("Calendrier — sombre", app: app)
        app.buttons["calendar.next"].tap()
        XCTAssertTrue(app.staticTexts["Aucun arrosage prévu ce jour"].exists)
    }

    func testCalendarAndFormWithLargestTextSize() {
        let app = launch(largeText: true)
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Calendrier"].tap()
        XCTAssertTrue(app.buttons["calendar.next"].waitForExistence(timeout: 5))
        capture("Calendrier — texte accessible", app: app)
        app.buttons["calendar.next"].tap()
        app.buttons["calendar.previous"].tap()
        app.tabBars.buttons["Mes plantes"].tap()
        app.buttons["plants.add"].tap()
        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 5))
        capture("Formulaire — texte accessible", app: app)
        app.buttons["Annuler"].tap()
    }
}
