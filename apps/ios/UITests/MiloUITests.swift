import XCTest

final class MiloUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false; recordTestBundleProvenance(Self.self) }

    @MainActor
    private func launch(id: String = UUID().uuidString, extra: [String] = [], login: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-id", id] + extra
        app.launch()
        if login, app.textFields["login-email"].waitForExistence(timeout: 3) {
            app.textFields["login-email"].tap()
            app.textFields["login-email"].typeText("milo")
            app.buttons["login-submit"].tap()
        }
        return app
    }
    @MainActor private func enterNow(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["confirm-mood"].waitForExistence(timeout: 10))
        app.buttons["confirm-mood"].tap()
        app.buttons["confirm-words"].tap()
        app.buttons["choose-now"].tap()
    }
    @MainActor private func input(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let field = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }
    @MainActor private func tap(_ id: String, in app: XCUIApplication) {
        if ["save-conversation", "finish-chat", "end-chat"].contains(id), !app.buttons[id].exists {
            app.buttons["chat-options"].tap()
        }
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        func visible() -> Bool {
            guard button.isHittable else { return false }
            if id.hasPrefix("card-template-") {
                let footer = app.buttons["save-card"]
                return footer.exists && button.frame.minY >= app.frame.minY + 8
                    && button.frame.maxY <= footer.frame.minY - 12
            }
            return true
        }
        for _ in 0..<10 {
            if visible() { break }
            // A card's header can move above the viewport after choosing a template.
            // Scroll toward the target instead of always moving further down the page.
            if button.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(visible(), "The visible page must expose the complete \(id) action above fixed controls")
        button.tap()
    }
    @MainActor private func capture(_ name: String, in app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    @MainActor private func assertCardTemplateGeometry(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["card-template-planet-letter"].isHittable)
        XCTAssertTrue(app.buttons["card-template-orbit-theatre"].isHittable)
        // One public AX snapshot gives every rectangle from the same instant.
        // There is no wait/retry and the one-point tolerance is unchanged.
        guard let snapshot = try? app.snapshot() else {
            XCTFail("Unable to read the actual template layout"); return
        }
        func flatten(_ item: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            [item] + item.children.flatMap { flatten($0) }
        }
        let nodes = flatten(snapshot)
        func node(_ id: String, button: Bool = false) -> (any XCUIElementSnapshot)? {
            nodes.first { $0.identifier == id && (!button || $0.elementType == .button) }
        }
        capture("card-templates-measured-state", in: app)
        let tree = XCTAttachment(string: String(describing: snapshot.dictionaryRepresentation))
        tree.name = "card-templates-measured-accessibility"; tree.lifetime = .keepAlways; add(tree)
        guard let first = node("card-template-planet-letter", button: true),
              let second = node("card-template-orbit-theatre", button: true),
              let heading = node("card-templates-heading"),
              let footer = node("save-card", button: true) else {
            XCTFail("Template buttons, heading and footer must exist in the same snapshot"); return
        }
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 1)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(heading.frame.minY, snapshot.frame.minY)
        XCTAssertGreaterThanOrEqual(first.frame.minY, heading.frame.maxY + 6)
        let footerTop = footer.frame.minY - 12
        var previewTops: [CGFloat] = []
        for (value, title, subtitle) in [
            ("planet-letter", "星球卡片", "雾紫卡纸"),
            ("orbit-theatre", "轨道剧场", "社交海报")
        ] {
            guard let button = node("card-template-" + value, button: true),
                  let preview = node("card-template-preview-" + value),
                  let titleText = node("card-template-title-" + value),
                  let subtitleText = node("card-template-subtitle-" + value) else {
                XCTFail("The template's complete preview, title and subtitle must remain accessible"); return
            }
            XCTAssertEqual(titleText.label, title); XCTAssertEqual(subtitleText.label, subtitle)
            XCTAssertGreaterThan(titleText.frame.height, 0); XCTAssertGreaterThan(subtitleText.frame.height, 0)
            for content in [preview, titleText, subtitleText] {
                XCTAssertTrue(button.frame.insetBy(dx: -1, dy: -1).contains(content.frame),
                              "The complete \(content.identifier) must stay inside its template button")
                XCTAssertLessThanOrEqual(content.frame.maxY, footerTop)
            }
            XCTAssertGreaterThanOrEqual(titleText.frame.minY, preview.frame.maxY)
            XCTAssertGreaterThanOrEqual(subtitleText.frame.minY, titleText.frame.maxY)
            XCTAssertLessThanOrEqual(button.frame.maxY, footerTop)
            XCTAssertEqual(preview.frame.width / preview.frame.height, 1.6, accuracy: 0.03)
            previewTops.append(preview.frame.minY)
        }
        XCTAssertEqual(previewTops[0], previewTops[1], accuracy: 1)
    }

    @MainActor private func scrollToCardTemplates(in app: XCUIApplication) {
        let identifier = "parity-scroll-collection-card"
        var viewport = parityViewport(identifier, in: app)
        for _ in 0..<12 {
            if viewport.offset >= viewport.maxOffset - 1 { break }
            parityDrag(viewport.frame, downward: false, in: app, edge: true)
            viewport = parityViewport(identifier, in: app)
        }
    }

    @MainActor func testChatCompactLayoutKeyboardAndLargeText() {
        for largeText in [false, true] {
            let caseID = largeText ? "chat--long-reply--large-text" : "chat--long-reply"
            let extra = ["--parity-case", caseID] + (largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
            let app = launch(extra: extra, login: false)
            let root = app.descendants(matching: .any).matching(identifier: "parity-root").firstMatch
            XCTAssertTrue(root.waitForExistence(timeout: 5))
            XCTAssertEqual(root.value as? String, largeText ? "accessibility5" : "large")
            let field = input("chat-input", in: app)
            XCTAssertTrue(app.buttons["chat-options"].isHittable)
            XCTAssertFalse(app.buttons["end-chat"].exists)
            XCTAssertFalse(app.buttons["finish-chat"].exists)
            field.tap(); field.typeText("我还有一些话想说。")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            let send = app.buttons["send-message"]
            XCTAssertTrue(send.isHittable)
            XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            capture(largeText ? "chat-compact-large-text-keyboard" : "chat-compact-keyboard", in: app)
            tap("chat-editor-done", in: app)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            tap("chat-capability-notice", in: app)
            XCTAssertTrue(app.staticTexts["chat-connection-detail"].waitForExistence(timeout: 5))
            capture(largeText ? "chat-compact-large-text-status" : "chat-compact-status", in: app)
            app.terminate()
        }
    }

    @MainActor func testPresentChatHonestOfflineExitResumeAndRawCollection() {
        let app = launch()
        tap("confirm-mood", in: app); tap("confirm-words", in: app); tap("choose-now-chat", in: app)
        XCTAssertFalse(app.buttons["start-chat"].exists)
        XCTAssertTrue(app.buttons["chat-capability-notice"].label.contains("仅本地记录"))
        XCTAssertFalse(app.staticTexts["chat-connection-detail"].exists)
        tap("chat-capability-notice", in: app)
        XCTAssertTrue(app.staticTexts["chat-connection-detail"].label.contains("未接通"))
        app.buttons["完成"].tap()
        let field = input("chat-input", in: app); field.tap(); field.typeText("今天心情不好，想吐槽")
        tap("send-message", in: app)
        XCTAssertTrue(app.buttons["chat-options"].isHittable)
        XCTAssertFalse(app.progressIndicators["chat-thinking-progress"].exists)
        XCTAssertFalse(app.buttons["retry-reply"].exists)
        tap("end-chat", in: app)
        XCTAssertTrue(app.buttons["resume-draft"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        tap("resume-draft", in: app)
        XCTAssertTrue(app.staticTexts["今天心情不好，想吐槽"].exists)
        tap("save-conversation", in: app); tap("card-done", in: app)
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.staticTexts["此刻"].exists)
        tap("toggle-transcript", in: app)
        XCTAssertTrue(app.staticTexts["我：今天心情不好，想吐槽"].exists)
        capture("present-offline-collected-raw-transcript", in: app)
    }

    @MainActor func testCancelledNewMoodKeepsRetainedConversationMoodAfterRestart() {
        let app = launch()
        tap("mood-bright", in: app); tap("confirm-mood", in: app); tap("confirm-words", in: app); tap("choose-now-chat", in: app)
        let field = input("chat-input", in: app); field.tap(); field.typeText("这份草稿要留着。")
        tap("send-message", in: app); tap("end-chat", in: app)
        tap("mood-low", in: app); tap("confirm-mood", in: app)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "取消", "Cancel")).firstMatch
        if cancel.exists { cancel.tap() }
        else {
            // Native popover-style confirmation hides its cancel-role button.
            // Tapping the dimmed area outside it is the system's cancel action.
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: sheet.frame.midX, dy: sheet.frame.minY - 24)).tap()
        }
        XCTAssertFalse(sheet.exists)
        app.terminate(); app.launch(); tap("resume-draft", in: app)
        XCTAssertTrue(app.staticTexts["这份草稿要留着。"].exists)
        tap("save-conversation", in: app); tap("card-done", in: app)
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.staticTexts["明亮"].exists, "cancelled home selection cannot persist a different mood in the old draft")
        XCTAssertFalse(app.staticTexts["低落"].exists)
        capture("cancel-new-mood-preserves-retained-draft", in: app)
    }

    @MainActor func testPresentOptionalLocalDiaryAndLongReplyVisibility() {
        let app = launch()
        tap("confirm-mood", in: app); tap("confirm-words", in: app); tap("choose-now-chat", in: app)
        let field = input("chat-input", in: app); field.tap(); field.typeText("今天开了一天会，最后被加活。")
        tap("send-message", in: app); tap("finish-chat", in: app)
        XCTAssertTrue(app.staticTexts["整理此刻"].exists)
        XCTAssertEqual(app.staticTexts["diary-content"].label, "今天开了一天会，最后被加活。")
        tap("save-past", in: app)
        XCTAssertTrue(app.buttons["card-done"].waitForExistence(timeout: 5))
        app.terminate()
        let longApp = launch(extra: ["--parity-case", "chat--long-reply"], login: false)
        let expected = "开了一天会之后还被加活，连着几天都是这样，确实没有多少喘口气的时间。\n先把你想说的话说完，不急着给建议。👩🏽‍🚀\n这是完整保留的最后一句。"
        let reply = longApp.staticTexts.matching(identifier: "message-2").matching(NSPredicate(format: "label == %@", expected)).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertEqual(reply.label, expected)
        XCTAssertTrue(reply.isHittable)
        capture("complete-long-reply-with-emoji-and-tail", in: longApp)
    }

    @MainActor func testContinuedChatKeepsPreviousEditedDiary() {
        let app = launch()
        tap("confirm-mood", in: app); tap("confirm-words", in: app); tap("choose-now-chat", in: app)
        let chat = input("chat-input", in: app); chat.tap(); chat.typeText("今天开了一天会。")
        tap("send-message", in: app); tap("finish-chat", in: app)
        tap("edit-diary", in: app)
        let editor = input("diary-editor", in: app); editor.tap(); editor.typeText("这是我亲手补写的内容。")
        // Finish the keyboard through its real accessory action before using
        // the page controls below the expanded multiline editor.
        let doneButtons = app.buttons.matching(NSPredicate(format: "label == %@", "完成编辑")).allElementsBoundByIndex
        guard let keyboardDone = doneButtons.first(where: { $0.isHittable }) else {
            XCTFail("The diary keyboard must expose its completion action"); return
        }
        keyboardDone.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        tap("back", in: app)
        let continued = input("chat-input", in: app); continued.tap(); continued.typeText("后来又被加活了。")
        tap("send-message", in: app); tap("finish-chat", in: app)
        XCTAssertTrue(app.staticTexts["diary-content"].label.contains("后来又被加活了。"))
        tap("previous-diary", in: app)
        XCTAssertTrue(app.staticTexts["previous-diary-content"].label.contains("这是我亲手补写的内容。"))
        capture("chat-preserved-edited-diary", in: app)
        tap("restore-previous-diary", in: app)
        XCTAssertTrue(app.staticTexts["diary-content"].label.contains("这是我亲手补写的内容。"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["diary-content"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["diary-content"].label.contains("这是我亲手补写的内容。"))
        tap("previous-diary", in: app)
        XCTAssertTrue(app.staticTexts["previous-diary-content"].label.contains("后来又被加活了。"))
    }

    @MainActor func testPresentJourneyAndRestartPersistence() {
        let app = launch()
        XCTAssertTrue(app.buttons["mood-bright"].waitForExistence(timeout: 10))
        app.buttons["mood-bright"].tap()
        enterNow(app)
        let note = input("note-input", in: app); note.tap(); note.typeText("今天散步很开心")
        tap("save-now", in: app)
        XCTAssertTrue(app.buttons["card-done"].waitForExistence(timeout: 5))
        tap("card-done", in: app)
        app.terminate(); app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertEqual(app.staticTexts["detail.content"].label, "今天散步很开心")
        XCTAssertTrue(app.staticTexts["明亮"].exists)
        capture("journey-present-detail", in: app)
    }

    @MainActor func testPastOfflineJourneyDiaryEditAndTemplatePersistence() {
        let app = launch()
        tap("confirm-mood", in: app); tap("confirm-words", in: app); tap("choose-past", in: app)
        XCTAssertFalse(app.buttons["start-chat"].isEnabled)
        tap("time-去年夏天", in: app); tap("start-chat", in: app)
        let field = input("chat-input", in: app); field.tap(); field.typeText("我记得那天和朋友一起散步。")
        tap("send-message", in: app)
        XCTAssertTrue(app.buttons["chat-options"].isHittable)
        tap("finish-chat", in: app)
        XCTAssertTrue(app.staticTexts["diary-content"].label.contains("和朋友一起散步"))
        tap("edit-diary", in: app)
        let diary = input("diary-editor", in: app); diary.tap(); diary.typeText("我想记住这一天。")
        tap("save-past", in: app)
        tap("card-template-orbit-theatre", in: app)
        XCTAssertTrue(app.buttons["card-template-orbit-theatre"].isSelected)
        assertCardTemplateGeometry(in: app)
        capture("journey-past-card-orbit", in: app)
        // Assert immediately after real switches; do not repair visibility by
        // scrolling in the test before checking the production layout.
        app.buttons["card-template-planet-letter"].tap()
        XCTAssertTrue(app.buttons["card-template-planet-letter"].isSelected)
        assertCardTemplateGeometry(in: app)
        capture("journey-past-card-planet-after-switch", in: app)
        app.buttons["card-template-orbit-theatre"].tap()
        XCTAssertTrue(app.buttons["card-template-orbit-theatre"].isSelected)
        assertCardTemplateGeometry(in: app)
        capture("journey-past-card-orbit-after-return", in: app)
        tap("card-done", in: app)
        app.terminate(); app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertTrue(app.staticTexts["detail.content"].label.contains("我想记住这一天"))
        tap("toggle-transcript", in: app)
        XCTAssertTrue(app.staticTexts["我：我记得那天和朋友一起散步。"].waitForExistence(timeout: 5))
        tap("open-card", in: app)
        XCTAssertTrue(app.buttons["card-template-orbit-theatre"].isSelected)
    }

    @MainActor func testBlankNoteAndEmptyCollection() {
        let app = launch()
        tap("open-timeline", in: app)
        XCTAssertTrue(app.staticTexts["这里还很安静"].waitForExistence(timeout: 5))
        tap("back", in: app); enterNow(app); tap("save-now", in: app)
        XCTAssertTrue(app.buttons["card-done"].waitForExistence(timeout: 5))
        tap("card-done", in: app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).count, 1)
    }

    @MainActor func testUnsentDraftRestoresAndChangingTimeClearsContext() {
        let app = launch()
        tap("confirm-mood", in: app); tap("confirm-words", in: app); tap("choose-past", in: app)
        tap("time-昨天", in: app); tap("start-chat", in: app)
        let field = input("chat-input", in: app); field.tap(); field.typeText("还没有说完的话")
        app.terminate(); app.launch()
        XCTAssertEqual(input("chat-input", in: app).value as? String, "还没有说完的话")
        tap("back", in: app); tap("time-小时候", in: app); tap("start-chat", in: app)
        XCTAssertFalse((input("chat-input", in: app).value as? String ?? "").contains("还没有说完"))
        XCTAssertTrue(app.staticTexts["「小时候」，你最先想起什么？"].exists)
    }

    @MainActor func testWriteFailureRetainsInputThenRecovers() {
        let id = UUID().uuidString
        let app = launch(id: id, extra: ["--uitest-write-failure"])
        enterNow(app)
        let field = input("note-input", in: app); field.tap(); field.typeText("失败也别丢掉这句话")
        tap("save-now", in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["知道了"].tap()
        XCTAssertEqual(input("note-input", in: app).value as? String, "失败也别丢掉这句话")
        app.terminate(); app.launchArguments = ["--uitest-id", id]; app.launch()
        XCTAssertEqual(input("note-input", in: app).value as? String, "失败也别丢掉这句话")
        tap("save-now", in: app)
        XCTAssertTrue(app.buttons["card-done"].waitForExistence(timeout: 5))
    }

    @MainActor func testCorruptStoreCannotBeRewritten() {
        let id = UUID().uuidString
        let app = launch(id: id, extra: ["--uitest-corrupt"], login: false)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["知道了"].tap()
        let email = app.textFields["login-email"]; email.tap(); email.typeText("milo"); app.buttons["login-submit"].tap()
        enterNow(app)
        XCTAssertFalse(app.buttons["save-now"].isEnabled)
        app.terminate(); app.launchArguments = ["--uitest-id", id]; app.launch()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["知道了"].tap()
        XCTAssertFalse(app.buttons["save-now"].isEnabled)
    }

    @MainActor func testLargeTextKeyboardKeepsSaveReachable() {
        let app = launch(extra: ["--parity-case", "now-note--keyboard-long--large-text"], login: false)
        let field = input("note-input", in: app)
        // Tap the editor's visible intersection above the fixed save action.
        let save = app.buttons["save-now"]
        let top = max(field.frame.minY, app.frame.minY + 110)
        let bottom = min(field.frame.maxY, save.frame.minY - 16)
        if bottom > top + 30 {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: field.frame.midX, dy: (top + bottom) / 2)).tap()
        } else { app.swipeUp(); field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        field.typeText("大字号输入也要保留下来。")
        XCTAssertTrue((field.value as? String ?? "").contains("大字号输入也要保留下来。"))
        let viewport = parityViewport("parity-scroll-note-editor", in: app)
        XCTAssertLessThanOrEqual(field.frame.maxY, save.frame.minY)
        XCTAssertEqual(viewport.raw["isFirstResponder"], 1)
        XCTAssertEqual(viewport.raw["selectionIsEmpty"], 1)
        XCTAssertGreaterThan(viewport.raw["caretHeight"] ?? 0, 0)
        XCTAssertGreaterThanOrEqual(viewport.raw["caretY"] ?? -1, viewport.frame.minY - 1)
        XCTAssertLessThanOrEqual((viewport.raw["caretY"] ?? 0) + (viewport.raw["caretHeight"] ?? 0), viewport.frame.maxY + 1)
        capture("now-note--keyboard-long--large-text--keyboard", in: app)
        save.tap()
        XCTAssertTrue(app.buttons["card-done"].waitForExistence(timeout: 5))
    }

    @MainActor func testDescriptorLimitAndReentryReset() {
        let app = launch()
        tap("confirm-mood", in: app)
        for index in 0...3 { tap("word-\(index)", in: app) }
        XCTAssertEqual((0..<12).filter { app.buttons["word-\($0)"].isSelected }.count, 3)
        tap("back", in: app); tap("confirm-mood", in: app)
        XCTAssertEqual((0..<12).filter { app.buttons["word-\($0)"].isSelected }.count, 0)
    }

    @MainActor func testBothCardTemplatesRenderForNativeShare() {
        for template in ["planet-letter", "orbit-theatre"] {
            let app = launch(extra: ["--parity-case", "card--" + template], login: false)
            tap("share-card", in: app)
            let sheet = app.descendants(matching: .any).matching(identifier: "card-share-sheet").firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 8), "A rendered PNG must reach native sharing for \(template)")
            capture("export-" + template + "-native-share", in: app)
            app.terminate()
        }
    }
    @MainActor func testLargeTextEditorTailRemainsVisibleAndPersists() {
        let app = launch(extra: ["--parity-case", "now-note--empty--large-text"], login: false)
        let field = input("note-input", in: app)
        for _ in 0..<6 { if field.isHittable { break }; app.swipeUp() }
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let text = Array(repeating: "今天慢慢走了一段路，风很温柔。我想记住这段安静的时间。", count: 3).joined(separator: "\n\n") + "\n这里是实际输入的最后一句。"
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
        let viewport = parityViewport("parity-scroll-note-editor", in: app)
        XCTAssertEqual(viewport.raw["isFirstResponder"], 1)
        XCTAssertEqual(viewport.raw["selectionIsEmpty"], 1)
        XCTAssertGreaterThan(viewport.raw["caretHeight"] ?? 0, 0)
        XCTAssertGreaterThanOrEqual(viewport.raw["caretY"] ?? -1, viewport.frame.minY - 1)
        XCTAssertLessThanOrEqual((viewport.raw["caretY"] ?? 0) + (viewport.raw["caretHeight"] ?? 0), viewport.frame.maxY + 1)
        capture("large-text-editor-actual-tail", in: app)
        tap("note-editor-done", in: app)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        tap("save-now", in: app); tap("card-done", in: app)
        // Relaunch the same isolated store without rebuilding the screenshot fixture.
        app.terminate(); app.launchArguments = Array(app.launchArguments.prefix(2)); app.launch()
        if app.textFields["login-email"].waitForExistence(timeout: 3) {
            app.textFields["login-email"].tap(); app.textFields["login-email"].typeText("milo")
            app.buttons["login-submit"].tap()
        }
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertEqual(app.staticTexts["detail.content"].label, text)
    }

    @MainActor func testCardTemplateGeometryAndLoginErrorState() {
        for template in ["planet-letter", "orbit-theatre"] {
            let app = launch(extra: ["--parity-case", "card--" + template], login: false)
            XCTAssertTrue(app.buttons["save-card"].isHittable)
            XCTAssertTrue(app.buttons["card-home"].isHittable)
            scrollToCardTemplates(in: app)
            assertCardTemplateGeometry(in: app)
            let other = template == "planet-letter" ? "orbit-theatre" : "planet-letter"
            app.buttons["card-template-" + other].tap()
            XCTAssertTrue(app.buttons["card-template-" + other].isSelected)
            assertCardTemplateGeometry(in: app)
            capture("template-switch-" + template + "-to-" + other, in: app)
            app.buttons["card-template-" + template].tap()
            XCTAssertTrue(app.buttons["card-template-" + template].isSelected)
            assertCardTemplateGeometry(in: app)
            capture("repaired-template-layout-" + template, in: app)
            app.terminate()
        }
        let largeTextApp = launch(extra: ["--parity-case", "timeline--populated--large-text"], login: false)
        let entry = largeTextApp.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        tap("open-card", in: largeTextApp)
        scrollToCardTemplates(in: largeTextApp)
        for template in ["orbit-theatre", "planet-letter"] {
            largeTextApp.buttons["card-template-" + template].tap()
            XCTAssertTrue(largeTextApp.buttons["card-template-" + template].isSelected)
            assertCardTemplateGeometry(in: largeTextApp)
            capture("template-switch-largest-text-" + template, in: largeTextApp)
        }
        largeTextApp.terminate()
        let app = launch(extra: ["--parity-case", "login--error"], login: false)
        assertParityState("login--error", in: app)
        capture("repaired-login-error", in: app)
    }

}
