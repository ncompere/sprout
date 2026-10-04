import XCTest

final class SproutUITests: XCTestCase {
    private var language = "fr"
    private var region = "fr_FR"

    private func copy(_ french: String) -> String {
        guard language == "en" else { return french }
        let english: [String: String] = [
            "1 plante": "1 plant",
            "Annuler": "Cancel",
            "Arrosage effectué": "Watering completed",
            "Arrosage non effectué": "Not watered",
            "Arrosage prévu": "Watering scheduled",
            "Arrosée aujourd’hui": "Watered today",
            "À arroser aujourd’hui": "Water today",
            "Aucun arrosage prévu ce jour": "No watering scheduled for this day",
            "Calendrier": "Calendar",
            "Choisir une photo": "Choose a photo",
            "Supprimer la photo": "Remove photo",
            "Terminé": "Done",
            "Mes plantes": "My plants",
            "En retard": "Overdue",
            "Nouvelle pièce": "New room",
            "OK": "OK",
            "Par arrosage": "By watering",
            "Par pièces": "By room",
            "Pièce": "Room",
            "Sans pièce": "No room",
            "Ses plantes seront déplacées vers « Sans pièce ». Les plantes et leurs arrosages seront conservés.": "Its plants will be moved to “No room”. The plants and their waterings will be kept.",
            "Supprimer": "Delete",
            "Supprimer la pièce": "Delete room",
            "Tous les 3 jours": "Every 3 days",
            "Tous les 7 jours": "Every 7 days",
            "Une pièce porte déjà ce nom.": "A room with this name already exists.",
        ]
        if let value = english[french] { return value }
        if french.hasPrefix("Renommer ") { return "Rename " + french.dropFirst("Renommer ".count) }
        if french.hasPrefix("Supprimer ") { return "Delete " + french.dropFirst("Supprimer ".count) }
        XCTFail("Missing English expectation for: \(french)")
        return french
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(style: String = "Light", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", region,
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
        attachment.name = "\(language) / \(region) — \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func assertWatering(_ watered: Bool, app: XCUIApplication,
                                status: String? = nil,
                                file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let checkbox = app.switches["plant.water"]
        // List creates offscreen rows lazily at the largest Dynamic Type sizes.
        for _ in 0..<6 {
            if checkbox.exists && checkbox.isHittable {
                let visibleBottom = app.tabBars.firstMatch.exists
                    ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
                if checkbox.frame.maxY <= visibleBottom { break }
            }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5), file: file, line: line)
        let value = copy(watered ? "Arrosage effectué" : "Arrosage non effectué")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: checkbox
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       file: file, line: line)
        XCTAssertEqual(checkbox.label, copy("Arrosée aujourd’hui"), file: file, line: line)
        XCTAssertTrue(checkbox.isEnabled, file: file, line: line)
        XCTAssertGreaterThanOrEqual(checkbox.frame.height, 44, file: file, line: line)
        // All three elements must remain in one native list cell when watering changes.
        let cards = app.cells.containing(.staticText, identifier: "plant.nextDue")
        XCTAssertEqual(cards.count, 1, file: file, line: line)
        let card = cards.firstMatch
        XCTAssertTrue(card.switches["plant.water"].exists, file: file, line: line)
        let wateringStatus = card.staticTexts["plant.wateringStatus"]
        XCTAssertTrue(wateringStatus.exists, file: file, line: line)
        if let expectedStatus = status ?? (watered ? "Arrosage prévu" : nil) {
            XCTAssertEqual(wateringStatus.label, copy(expectedStatus), file: file, line: line)
        }
        return checkbox
    }

    private func checkWateringPresentation(app: XCUIApplication, name: String) {
        app.buttons["plants.add"].tap()
        app.textFields["editor.name"].tap()
        app.textFields["editor.name"].typeText(name)
        app.buttons["editor.save"].tap()
        for _ in 0..<6 {
            if app.staticTexts[name].exists { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        reveal(app.staticTexts[name], app: app)
        app.staticTexts[name].tap()
        assertWatering(false, app: app, status: "À arroser aujourd’hui")
        let initialDue = app.staticTexts["plant.nextDue"].label
        capture("Case vide — \(name)", app: app)
        assertWatering(false, app: app).tap()
        assertWatering(true, app: app)
        XCTAssertNotEqual(app.staticTexts["plant.nextDue"].label, initialDue)
        capture("Case cochée — \(name)", app: app)
        assertWatering(true, app: app).tap()
        assertWatering(false, app: app, status: "À arroser aujourd’hui")
        XCTAssertEqual(app.staticTexts["plant.nextDue"].label, initialDue)
        capture("Case décochée — \(name)", app: app)
        let delete = app.buttons["plant.delete"]
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["plant.confirmDelete"].tap()
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[name].exists)
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        // Short drags avoid skipping a section header between large Dynamic Type rows.
        for _ in 0..<16 {
            let list = app.collectionViews.firstMatch
            if element.exists && element.isHittable {
                let frame = element.frame
                let visibleBottom = min(list.frame.maxY, app.frame.maxY - 34)
                // A partially visible button can report hittable while its tap lands below the sheet.
                if frame.maxY <= visibleBottom { break }
            }
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo:
                    list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        if !element.exists { print(app.debugDescription) }
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func openPlant(_ name: String, app: XCUIApplication) {
        reveal(app.staticTexts[name], app: app)
        app.staticTexts[name].tap()
    }

    private func deleteRoom(_ name: String, app: XCUIApplication) {
        let button = app.buttons[copy("Supprimer \(name)")]
        reveal(button, app: app)
        button.tap()
        XCTAssertTrue(app.staticTexts[copy("Ses plantes seront déplacées vers « Sans pièce ». Les plantes et leurs arrosages seront conservés.")].waitForExistence(timeout: 5))
        app.buttons["rooms.confirmDelete"].tap()
        XCTAssertFalse(button.waitForExistence(timeout: 1))
    }

    private func checkRoomPresentation(app: XCUIApplication, suffix: String) {
        let roomName = "Salon \(suffix)"
        app.buttons["plants.rooms"].tap()
        XCTAssertTrue(app.buttons["rooms.add"].waitForExistence(timeout: 5))
        app.buttons["rooms.add"].tap()
        XCTAssertFalse(app.buttons["roomEditor.save"].isEnabled)
        app.textFields["roomEditor.name"].tap()
        app.textFields["roomEditor.name"].typeText(roomName)
        capture("Nouvelle pièce — \(suffix)", app: app)
        app.buttons["roomEditor.save"].tap()
        reveal(app.buttons[copy("Renommer \(roomName)")], app: app)
        let roomID = String(app.buttons[copy("Renommer \(roomName)")].identifier.dropFirst("rooms.edit.".count))
        capture("Gestion des pièces — \(suffix)", app: app)
        app.buttons["rooms.close"].tap()
        app.segmentedControls["plants.grouping"].buttons[copy("Par pièces")].tap()
        let header = app.staticTexts["plants.room.\(roomID)"]
        reveal(header, app: app)
        XCTAssertEqual(header.label, roomName)
        capture("Pièce vide — \(suffix)", app: app)
        app.buttons["plants.add"].tap()
        let picker = app.descendants(matching: .any)["editor.room"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        capture("Sélecteur de pièce avant choix — \(suffix)", app: app)
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44)
        picker.tap()
        app.buttons[roomName].tap()
        capture("Choix de pièce — \(suffix)", app: app)
        app.buttons["editor.cancel"].tap()
        app.buttons["plants.rooms"].tap()
        deleteRoom(roomName, app: app)
        app.buttons["rooms.close"].tap()
    }

    private func checkRoomsLifecycleAndRememberedGrouping() {
        let app = launch()
        let suffix = String(UUID().uuidString.prefix(6))
        let name = "Ficus pièces \(suffix)"
        let salon = "Salon \(suffix)"
        let bureau = "Bureau \(suffix)"
        let atelier = "Atelier \(suffix)"
        app.segmentedControls["plants.grouping"].buttons[copy("Par pièces")].tap()
        app.buttons["plants.add"].tap()
        app.textFields["editor.name"].tap()
        app.textFields["editor.name"].typeText(name)
        app.buttons["editor.createRoom"].tap()
        app.textFields["roomEditor.name"].tap()
        app.textFields["roomEditor.name"].typeText(salon)
        app.buttons["roomEditor.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.room"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["editor.room"].label.contains(salon))
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts[salon].waitForExistence(timeout: 5))
        openPlant(name, app: app)
        XCTAssertEqual(app.staticTexts["plant.room"].label, salon)
        assertWatering(false, app: app).tap()
        let due = app.staticTexts["plant.nextDue"].label
        app.buttons["plant.edit"].tap()
        app.buttons["editor.createRoom"].tap()
        app.textFields["roomEditor.name"].tap()
        app.textFields["roomEditor.name"].typeText(bureau)
        app.buttons["roomEditor.save"].tap()
        app.buttons["editor.save"].tap()
        XCTAssertEqual(app.staticTexts["plant.room"].label, bureau)
        XCTAssertEqual(app.staticTexts["plant.nextDue"].label, due)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["plants.rooms"].tap()
        let rename = app.buttons[copy("Renommer \(bureau)")]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        XCTAssertEqual(rename.value as? String, copy("1 plante"))
        rename.tap()
        let field = app.textFields["roomEditor.name"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: bureau.count) + atelier)
        app.buttons["roomEditor.save"].tap()
        XCTAssertTrue(app.buttons[copy("Renommer \(atelier)")].waitForExistence(timeout: 5))
        capture("Pièces — clair", app: app)
        app.buttons["rooms.add"].tap()
        let duplicateName = atelier.uppercased()
        app.textFields["roomEditor.name"].tap()
        app.textFields["roomEditor.name"].typeText(duplicateName)
        app.buttons["roomEditor.save"].tap()
        XCTAssertTrue(app.alerts.staticTexts[copy("Une pièce porte déjà ce nom.")].waitForExistence(timeout: 5))
        app.alerts.buttons[copy("OK")].tap()
        XCTAssertEqual(app.textFields["roomEditor.name"].value as? String, duplicateName)
        app.buttons["roomEditor.cancel"].tap()
        app.buttons["rooms.close"].tap()
        XCTAssertTrue(app.staticTexts[atelier].waitForExistence(timeout: 5))
        capture("Organisation par pièces avec affectation — clair", app: app)
        app.segmentedControls["plants.grouping"].buttons[copy("Par arrosage")].tap()
        capture("Organisation par arrosage — clair", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.segmentedControls["plants.grouping"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls["plants.grouping"].buttons[copy("Par arrosage")].isSelected)
        openPlant(name, app: app)
        XCTAssertEqual(app.staticTexts["plant.room"].label, atelier)
        assertWatering(true, app: app)
        app.buttons["plant.edit"].tap()
        app.descendants(matching: .any)["editor.room"].tap()
        app.buttons[copy("Sans pièce")].tap()
        app.buttons["editor.save"].tap()
        XCTAssertEqual(app.staticTexts["plant.room"].label, copy("Sans pièce"))
        app.buttons["plant.edit"].tap()
        app.descendants(matching: .any)["editor.room"].tap()
        app.buttons[atelier].tap()
        app.buttons["editor.save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["plants.rooms"].tap()
        deleteRoom(atelier, app: app)
        deleteRoom(salon, app: app)
        app.buttons["rooms.close"].tap()
        app.segmentedControls["plants.grouping"].buttons[copy("Par pièces")].tap()
        reveal(app.staticTexts[copy("Sans pièce")], app: app)
        capture("Organisation par pièces — clair", app: app)
        app.terminate()
        app.launch()
        openPlant(name, app: app)
        XCTAssertEqual(app.staticTexts["plant.room"].label, copy("Sans pièce"))
        assertWatering(true, app: app)
        XCTAssertEqual(app.staticTexts["plant.nextDue"].label, due)
        let delete = app.buttons["plant.delete"]
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["plant.confirmDelete"].tap()
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[name].exists)
    }

    private func checkPlantLifecycleAndCalendar() {
        let app = launch()
        let name = "Monstera test \(UUID().uuidString.prefix(6))"
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 10))
        capture("Mes plantes — clair", app: app)
        app.buttons["plants.add"].tap()
        XCTAssertFalse(app.buttons["editor.save"].isEnabled)
        app.textFields["editor.name"].tap()
        app.textFields["editor.name"].typeText(name)
        app.buttons["editor.save"].tap()
        reveal(app.staticTexts[name], app: app)
        capture("Plante ajoutée", app: app)
        app.staticTexts[name].tap()
        let checkbox = assertWatering(false, app: app)
        XCTAssertTrue(app.staticTexts[copy("Tous les 7 jours")].exists)
        capture("Case d’arrosage vide — clair", app: app)
        let initialDue = app.staticTexts["plant.nextDue"].label
        // Touch the square, then touch the label to undo the same watering.
        checkbox.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 12, dy: checkbox.frame.height / 2)).tap()
        assertWatering(true, app: app)
        capture("Arrosage enregistré", app: app)
        checkbox.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 100, dy: checkbox.frame.height / 2)).tap()
        assertWatering(false, app: app)
        XCTAssertEqual(app.staticTexts["plant.nextDue"].label, initialDue)
        app.tabBars.buttons[copy("Calendrier")].tap()
        let calendarRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(calendarRow.waitForExistence(timeout: 5))
        XCTAssertTrue(calendarRow.label.contains(copy("Arrosage prévu")))
        XCTAssertFalse(calendarRow.label.contains(copy("Arrosage effectué")))
        app.terminate()
        app.launch()
        reveal(app.staticTexts[name], app: app)
        app.staticTexts[name].tap()
        assertWatering(false, app: app).tap()
        assertWatering(true, app: app)
        app.buttons["plant.edit"].tap()
        let interval = app.textFields["editor.interval"]
        reveal(interval, app: app)
        interval.tap()
        interval.typeText(XCUIKeyboardKey.delete.rawValue + "0")
        XCTAssertFalse(app.buttons["editor.save"].isEnabled)
        interval.typeText(XCUIKeyboardKey.delete.rawValue + "3")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts[copy("Tous les 3 jours")].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        reveal(app.staticTexts[name], app: app)
        app.tabBars.buttons[copy("Calendrier")].tap()
        XCTAssertTrue(app.buttons["calendar.next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[copy("Arrosage effectué")].exists)
        capture("Calendrier — clair", app: app)
        let calendar = Calendar(identifier: .gregorian)
        let due = calendar.date(byAdding: .day, value: 3, to: Date.now)!
        if !calendar.isDate(due, equalTo: .now, toGranularity: .month) {
            app.buttons["calendar.next"].tap()
        }
        app.buttons["calendar.day.\(calendar.component(.day, from: due))"].tap()
        XCTAssertTrue(app.staticTexts[copy("Arrosage prévu")].exists)
        app.buttons["calendar.today"].tap()
        let oldMonth = app.staticTexts["calendar.month"].label
        app.buttons["calendar.next"].tap()
        XCTAssertNotEqual(app.staticTexts["calendar.month"].label, oldMonth)
        app.buttons["calendar.previous"].tap()
        XCTAssertEqual(app.staticTexts["calendar.month"].label, oldMonth)
        app.buttons["calendar.today"].tap()
        app.tabBars.buttons[copy("Mes plantes")].tap()
        app.staticTexts[name].tap()
        assertWatering(true, app: app)
        app.buttons["plant.delete"].tap()
        app.buttons["plant.confirmDelete"].tap()
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[name].exists)
    }

    private func checkDarkCalendarAndEmptyState() {
        let app = launch(style: "Dark")
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 10))
        capture("Mes plantes — sombre", app: app)
        app.tabBars.buttons[copy("Calendrier")].tap()
        XCTAssertTrue(app.buttons["calendar.today"].waitForExistence(timeout: 5))
        capture("Calendrier — sombre", app: app)
        app.buttons["calendar.next"].tap()
        // Existing plants can have a watering on the first day of the next month.
        let emptySummary = language == "fr" ? "0 arrosage prévu. 0 arrosage effectué."
            : "0 waterings scheduled. 0 waterings completed."
        let emptyDay = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'calendar.day.' AND value == %@", emptySummary)).firstMatch
        XCTAssertTrue(emptyDay.waitForExistence(timeout: 5))
        emptyDay.tap()
        XCTAssertTrue(app.staticTexts[copy("Aucun arrosage prévu ce jour")].exists)
        app.tabBars.buttons[copy("Mes plantes")].tap()
        checkRoomPresentation(app: app, suffix: "sombre \(UUID().uuidString.prefix(6))")
        checkWateringPresentation(app: app, name: "Case sombre \(UUID().uuidString.prefix(6))")
    }

    private func checkCalendarAndFormWithLargestTextSize() {
        let app = launch(largeText: true)
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 10))
        app.tabBars.buttons[copy("Calendrier")].tap()
        XCTAssertTrue(app.buttons["calendar.next"].waitForExistence(timeout: 5))
        capture("Calendrier — texte accessible", app: app)
        app.buttons["calendar.next"].tap()
        app.buttons["calendar.previous"].tap()
        app.tabBars.buttons[copy("Mes plantes")].tap()
        app.buttons["plants.add"].tap()
        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 5))
        capture("Formulaire — texte accessible", app: app)
        app.buttons["editor.cancel"].tap()
        checkRoomPresentation(app: app, suffix: "texte agrandi \(UUID().uuidString.prefix(6))")
        checkWateringPresentation(app: app, name: "Case agrandie \(UUID().uuidString.prefix(6))")
    }

    func testRoomsLifecycleAndRememberedGroupingFrench() {
        language = "fr"
        region = "fr_FR"
        checkRoomsLifecycleAndRememberedGrouping()
    }

    // Seed the simulator photo library with `xcrun simctl addmedia <device> <image>` before running these flows.
    private func selectLibraryPhoto(app: XCUIApplication) throws {
        let choose = app.buttons["editor.photo.choose"]
        reveal(choose, app: app)
        XCTAssertEqual(choose.label, copy("Choisir une photo"))
        choose.tap()
        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 5))
        // At accessibility sizes, the system's information banner can fill the first screen.
        let closeInfo = app.buttons.matching(NSPredicate(format: "label == 'Fermer' OR label == 'Close'")).firstMatch
        if closeInfo.exists && closeInfo.isHittable { closeInfo.tap() }
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] 'Photo,'")).firstMatch
        for _ in 0..<5 {
            if photo.exists && photo.isHittable { break }
            let scrollViews = app.scrollViews
            guard scrollViews.count > 0 else { break }
            scrollViews.element(boundBy: scrollViews.count - 1).swipeUp()
        }
        guard photo.waitForExistence(timeout: 10) else {
            print(app.debugDescription)
            XCTFail("The native picker must contain a photo. Seed the simulator library before running these flows.")
            return
        }
        photo.tap()
        XCTAssertTrue(app.images["editor.photo.preview"].waitForExistence(timeout: 15))
    }

    private func checkPhotoLifecycle(style: String = "Light", largeText: Bool = false) throws {
        let app = launch(style: style, largeText: largeText)
        let name = "Photo test \(UUID().uuidString.prefix(6))"
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 10))
        app.buttons["plants.add"].tap()
        app.textFields["editor.name"].tap()
        app.textFields["editor.name"].typeText(name)
        if app.keyboards.firstMatch.exists { app.buttons[copy("Terminé")].tap() }
        try selectLibraryPhoto(app: app)
        capture("Photo — formulaire", app: app)
        app.buttons["editor.save"].tap()
        reveal(app.staticTexts[name], app: app)
        capture("Photo — liste", app: app)
        app.staticTexts[name].tap()
        XCTAssertTrue(app.images["plant.photo"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.images["plant.photo"].frame.height, 48)
        capture("Photo — fiche", app: app)
        assertWatering(false, app: app).tap()
        app.buttons["plant.edit"].tap()
        let remove = app.buttons["editor.photo.remove"]
        reveal(remove, app: app)
        XCTAssertEqual(remove.label, copy("Supprimer la photo"))
        remove.tap()
        XCTAssertTrue(app.images["editor.photo.preview"].waitForNonExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()
        for _ in 0..<8 {
            if app.images["plant.photo"].exists && app.images["plant.photo"].isHittable { break }
            app.collectionViews.firstMatch.swipeDown()
        }
        reveal(app.images["plant.photo"], app: app)
        app.buttons["plant.edit"].tap()
        try selectLibraryPhoto(app: app)
        app.buttons["editor.save"].tap()
        app.terminate()
        app.launch()
        reveal(app.staticTexts[name], app: app)
        app.staticTexts[name].tap()
        XCTAssertTrue(app.images["plant.photo"].waitForExistence(timeout: 5))
        assertWatering(true, app: app)
        app.buttons["plant.edit"].tap()
        reveal(app.buttons["editor.photo.remove"], app: app)
        app.buttons["editor.photo.remove"].tap()
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.images["plant.photo"].waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        reveal(app.staticTexts[name], app: app)
        app.staticTexts[name].tap()
        XCTAssertFalse(app.images["plant.photo"].exists)
        assertWatering(true, app: app)
        reveal(app.buttons["plant.delete"], app: app)
        app.buttons["plant.delete"].tap()
        app.buttons["plant.confirmDelete"].tap()
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[name].exists)
    }

    func testPlantPhotoLifecycleFrench() throws {
        language = "fr"
        region = "fr_FR"
        try checkPhotoLifecycle()
    }

    func testPlantPhotoLifecycleEnglishDark() throws {
        language = "en"
        region = "en_US"
        try checkPhotoLifecycle(style: "Dark")
    }

    func testPlantPhotoLifecycleFrenchLargestText() throws {
        language = "fr"
        region = "fr_FR"
        try checkPhotoLifecycle(largeText: true)
    }

    func testPlantLifecycleAndCalendarFrench() {
        language = "fr"
        region = "fr_FR"
        checkPlantLifecycleAndCalendar()
    }

    private func checkOverdueWateringCard() {
        let app = launch()
        let name = "Arrosage en retard \(UUID().uuidString.prefix(6))"
        app.buttons["plants.add"].tap()
        app.textFields["editor.name"].tap()
        app.textFields["editor.name"].typeText(name)
        if app.keyboards.firstMatch.exists { app.buttons[copy("Terminé")].tap() }
        let date = app.datePickers["editor.firstDate"]
        reveal(date, app: app)
        date.tap()
        let calendarPicker = app.datePickers.containing(.button, identifier: "DatePicker.PreviousMonth").firstMatch
        let month = calendarPicker.buttons["DatePicker.Show"]
        let initialMonth = month.value as? String ?? ""
        calendarPicker.buttons["DatePicker.PreviousMonth"].tap()
        let monthChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialMonth), object: month
        )
        XCTAssertEqual(XCTWaiter.wait(for: [monthChanged], timeout: 5), .completed)
        let firstOfMonth = calendarPicker.buttons.containing(.staticText, identifier: "1").firstMatch
        XCTAssertTrue(firstOfMonth.waitForExistence(timeout: 5))
        firstOfMonth.tap()
        XCTAssertTrue(firstOfMonth.isSelected)
        // The native compact picker can remain open after selecting its date.
        if app.buttons["DatePicker.PreviousMonth"].exists {
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        app.buttons["editor.save"].tap()
        openPlant(name, app: app)
        assertWatering(false, app: app, status: "En retard")
        let initialDue = app.staticTexts["plant.nextDue"].label
        capture("Carte en retard", app: app)
        assertWatering(false, app: app).tap()
        assertWatering(true, app: app)
        XCTAssertNotEqual(app.staticTexts["plant.nextDue"].label, initialDue)
        capture("Carte en retard — arrosage enregistré", app: app)
        assertWatering(true, app: app).tap()
        assertWatering(false, app: app, status: "En retard")
        XCTAssertEqual(app.staticTexts["plant.nextDue"].label, initialDue)
        capture("Carte en retard — arrosage annulé", app: app)
        reveal(app.buttons["plant.delete"], app: app)
        app.buttons["plant.delete"].tap()
        app.buttons["plant.confirmDelete"].tap()
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[name].exists)
    }

    func testWateringCardOverdueFrench() {
        language = "fr"
        region = "fr_FR"
        checkOverdueWateringCard()
    }

    func testWateringCardOverdueEnglish() {
        language = "en"
        region = "en_US"
        checkOverdueWateringCard()
    }

    func testDarkCalendarAndEmptyStateFrench() {
        language = "fr"
        region = "fr_FR"
        checkDarkCalendarAndEmptyState()
    }

    func testCalendarAndFormWithLargestTextSizeFrench() {
        language = "fr"
        region = "fr_FR"
        checkCalendarAndFormWithLargestTextSize()
    }

    func testRoomsLifecycleAndRememberedGroupingEnglish() {
        language = "en"
        region = "en_US"
        checkRoomsLifecycleAndRememberedGrouping()
    }

    func testPlantLifecycleAndCalendarEnglish() {
        language = "en"
        region = "en_US"
        checkPlantLifecycleAndCalendar()
    }

    func testDarkCalendarAndEmptyStateEnglish() {
        language = "en"
        region = "en_US"
        checkDarkCalendarAndEmptyState()
    }

    func testCalendarAndFormWithLargestTextSizeEnglish() {
        language = "en"
        region = "en_US"
        checkCalendarAndFormWithLargestTextSize()
    }

    func testPlantLifecycleEnglishWithFrenchRegion() {
        language = "en"
        region = "en_FR"
        checkPlantLifecycleAndCalendar()
    }

    func testLanguageChangePreservesPlantAndWatering() {
        let app = launch()
        let name = "Érable langue \(UUID().uuidString.prefix(6))"
        app.buttons["plants.add"].tap()
        app.textFields["editor.name"].tap()
        app.textFields["editor.name"].typeText(name)
        app.buttons["editor.save"].tap()
        openPlant(name, app: app)
        assertWatering(false, app: app).tap()
        assertWatering(true, app: app)
        let frenchDue = app.staticTexts["plant.nextDue"].label
        capture("Fiche avant changement de langue", app: app)
        app.terminate()
        language = "en"
        region = "en_FR"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", region, "--uitest-light"]
        app.launch()
        openPlant(name, app: app)
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, name)
        XCTAssertEqual(app.staticTexts["plant.room"].label, "No room")
        XCTAssertTrue(app.staticTexts["Every 7 days"].exists)
        assertWatering(true, app: app)
        let englishDue = app.staticTexts["plant.nextDue"].label
        XCTAssertNotEqual(englishDue, frenchDue)
        let calendar = Calendar(identifier: .gregorian)
        let due = calendar.date(byAdding: .day, value: 7, to: Date.now)!
        XCTAssertEqual(englishDue, due.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "en_FR"))))
        capture("Fiche après changement de langue", app: app)
        assertWatering(true, app: app).tap()
        assertWatering(false, app: app)
        app.buttons["plant.delete"].tap()
        app.buttons["plant.confirmDelete"].tap()
        XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[name].exists)
    }

    func testCalendarRegionsAndTranslatedValidation() {
        for (appLanguage, appRegion, firstWeekday) in [("fr", "fr_FR", 2), ("en", "en_US", 1), ("en", "en_FR", 2)] {
            language = appLanguage
            region = appRegion
            let app = launch()
            XCTAssertTrue(app.buttons["plants.add"].waitForExistence(timeout: 10))
            app.tabBars.buttons[copy("Calendrier")].tap()
            XCTAssertTrue(app.buttons["calendar.today"].waitForExistence(timeout: 5))
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday
            let month = calendar.dateInterval(of: .month, for: Date.now)!
            let leading = (calendar.component(.weekday, from: month.start) - firstWeekday + 7) % 7
            let first = app.buttons["calendar.day.1"]
            let firstColumn = app.buttons["calendar.day.\(8 - leading)"]
            XCTAssertTrue(first.exists)
            XCTAssertTrue(firstColumn.exists)
            XCTAssertEqual(first.frame.minX - firstColumn.frame.minX,
                           CGFloat(leading) * (first.frame.width + 1), accuracy: 2)
            let monthName = Date.now.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: appRegion)))
            XCTAssertEqual(app.staticTexts["calendar.month"].label, monthName.capitalized(with: Locale(identifier: appRegion)))
            let today = app.buttons["calendar.day.\(calendar.component(.day, from: Date.now))"]
            let summary = today.value as? String ?? ""
            XCTAssertTrue(summary.hasPrefix(appLanguage == "fr" ? "Aujourd’hui." : "Today."))
            XCTAssertTrue(summary.contains(appLanguage == "fr" ? "arrosage" : "watering"))
            XCTAssertFalse(summary.contains("(s)"))
            capture("Calendrier et premier jour régional", app: app)
            app.tabBars.buttons[copy("Mes plantes")].tap()
            app.buttons["plants.add"].tap()
            app.textFields["editor.name"].tap()
            app.textFields["editor.name"].typeText("Validation")
            app.buttons[appLanguage == "fr" ? "Terminé" : "Done"].tap()
            let interval = app.textFields["editor.interval"]
            interval.tap()
            interval.typeText(XCUIKeyboardKey.delete.rawValue + "0")
            XCTAssertFalse(app.buttons["editor.save"].isEnabled)
            let message = appLanguage == "fr" ? "Saisissez un nombre entier de jours supérieur ou égal à 1."
                : "Enter a whole number of days greater than or equal to 1."
            XCTAssertTrue(app.staticTexts[message].exists)
            app.buttons[appLanguage == "fr" ? "Terminé" : "Done"].tap()
            reveal(app.staticTexts[message], app: app)
            capture("Validation de fréquence traduite", app: app)
            app.buttons["editor.cancel"].tap()
            app.terminate()
        }
    }
}
