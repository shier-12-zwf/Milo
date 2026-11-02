import XCTest

/// Captures real production views with isolated synthetic stores. These are
/// candidates for comparison, never an automatic visual approval.
final class ParityCaptureTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; recordTestBundleProvenance(Self.self) }
    @MainActor func test_login__email() { captureCase("login--email") }
    @MainActor func test_login__password() { captureCase("login--password") }
    @MainActor func test_login__code() { captureCase("login--code") }
    @MainActor func test_login__reset() { captureCase("login--reset") }
    @MainActor func test_login__error() { captureCase("login--error") }
    @MainActor func test_home__mood_calm() { captureCase("home--mood-calm") }
    @MainActor func test_home__mood_joyful() { captureCase("home--mood-joyful") }
    @MainActor func test_home__mood_low() { captureCase("home--mood-low") }
    @MainActor func test_home__words_empty() { captureCase("home--words-empty") }
    @MainActor func test_home__words_three() { captureCase("home--words-three") }
    @MainActor func test_classify__default() { captureCase("classify--default") }
    @MainActor func test_now_note__empty() { captureCase("now-note--empty") }
    @MainActor func test_now_note__written() { captureCase("now-note--written") }
    @MainActor func test_now_note__keyboard_long() { captureCase("now-note--keyboard-long") }
    @MainActor func test_past_time__empty() { captureCase("past-time--empty") }
    @MainActor func test_past_time__preset() { captureCase("past-time--preset") }
    @MainActor func test_past_time__custom() { captureCase("past-time--custom") }
    @MainActor func test_chat__opening() { captureCase("chat--opening") }
    @MainActor func test_chat__conversation() { captureCase("chat--conversation") }
    @MainActor func test_chat__offline() { captureCase("chat--offline") }
    @MainActor func test_chat__keyboard() { captureCase("chat--keyboard") }
    @MainActor func test_chat__busy() { captureCase("chat--busy") }
    @MainActor func test_diary__enabled() { captureCase("diary--enabled") }
    @MainActor func test_diary__disabled() { captureCase("diary--disabled") }
    @MainActor func test_diary__editing() { captureCase("diary--editing") }
    @MainActor func test_diary__long() { captureCase("diary--long") }
    @MainActor func test_timeline__empty() { captureCase("timeline--empty") }
    @MainActor func test_timeline__populated() { captureCase("timeline--populated") }
    @MainActor func test_detail__now() { captureCase("detail--now") }
    @MainActor func test_detail__past() { captureCase("detail--past") }
    @MainActor func test_detail__transcript_expanded() { captureCase("detail--transcript-expanded") }
    @MainActor func test_detail__missing() { captureCase("detail--missing") }
    @MainActor func test_detail__delete_confirmation() { captureCase("detail--delete-confirmation") }
    @MainActor func test_card__planet_letter() { captureCase("card--planet-letter") }
    @MainActor func test_card__orbit_theatre() { captureCase("card--orbit-theatre") }
    @MainActor func test_account__local() { captureCase("account--local") }
    @MainActor func test_account__remote() { captureCase("account--remote") }
    @MainActor func test_account__password_form() { captureCase("account--password-form") }
    @MainActor func test_account__export() { captureCase("account--export") }
    @MainActor func test_account__delete_confirmation() { captureCase("account--delete-confirmation") }
    @MainActor func test_ai_settings__hosted() { captureCase("ai-settings--hosted") }
    @MainActor func test_ai_settings__personal() { captureCase("ai-settings--personal") }
    @MainActor func test_ai_settings__missing_config() { captureCase("ai-settings--missing-config") }
    @MainActor func test_ai_settings__consent() { captureCase("ai-settings--consent") }
    @MainActor func test_ai_settings__connection_error() { captureCase("ai-settings--connection-error") }
    @MainActor func test_home__words_three__large_text() { captureCase("home--words-three--large-text") }
    @MainActor func test_now_note__keyboard_long__large_text() { captureCase("now-note--keyboard-long--large-text") }
    @MainActor func test_chat__conversation__large_text() { captureCase("chat--conversation--large-text") }
    @MainActor func test_diary__long__large_text() { captureCase("diary--long--large-text") }
    @MainActor func test_timeline__populated__large_text() { captureCase("timeline--populated--large-text") }
    @MainActor func test_detail__transcript_expanded__large_text() { captureCase("detail--transcript-expanded--large-text") }
    @MainActor func test_account__local__large_text() { captureCase("account--local--large-text") }
    @MainActor func test_ai_settings__personal__large_text() { captureCase("ai-settings--personal--large-text") }
    @MainActor private func captureCase(_ caseID: String) {
            let app = XCUIApplication()
            app.launchArguments = ["--uitest-id", UUID().uuidString, "--parity-case", caseID]
            app.launch()
            let root = app.otherElements["parity-root"]
            XCTAssertTrue(root.waitForExistence(timeout: 10), caseID)
            XCTAssertEqual(root.value as? String, caseID.hasSuffix("--large-text") ? "accessibility5" : "large", caseID)
            let state = caseID.components(separatedBy: "--")[1]
            if ["keyboard", "keyboard-long"].contains(state) {
                let fieldID = caseID.hasPrefix("chat") ? "chat-input" : "note-input"
                let field = parityProbe(fieldID, in: app)
                XCTAssertTrue(field.exists)
                if !app.keyboards.firstMatch.exists {
                    // Reach the editor before tapping. Avoid drags on ring controls.
                    for _ in 0..<8 {
                        if field.isHittable { break }
                        app.swipeUp(velocity: .slow)
                    }
                    field.tap()
                }
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), caseID)
                Thread.sleep(forTimeInterval: 0.4)
                parityAssertKeyboardVisible(in: app)
            }
            assertParityState(caseID, in: app)
            if caseID == "login--error" { XCTAssertTrue(parityProbe("login-error-message", in: app).isHittable) }
            // A modal's underlying page is not evidence of the modal state.
            if caseID.contains("confirmation") {
                attach(caseID + "--top", app: app)
                assertParityState(caseID, in: app)
                app.terminate(); return
            }
            var remainingImages = 60
            if caseID.hasPrefix("now-note--keyboard-long") {
                captureEntireViewport(caseID, region: "page", identifier: "parity-scroll-journey-now-note", app: app, remainingImages: &remainingImages)
                parityAlignEditor(in: app)
                captureEntireViewport(caseID, region: "editor", identifier: "parity-scroll-note-editor", app: app, remainingImages: &remainingImages)
            } else {
                let probes = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "parity-scroll-")).allElementsBoundByIndex
                if let identifier = probes.first(where: { $0.identifier != "parity-scroll-note-editor" })?.identifier {
                    captureEntireViewport(caseID, region: "page", identifier: identifier, app: app, remainingImages: &remainingImages)
                } else {
                    XCTAssertFalse(app.scrollViews.firstMatch.exists, "A scrollable page requires measured coverage: \(caseID)")
                    attach(caseID + "--top", app: app)
                }
            }
            assertParityState(caseID, in: app)
            app.terminate()
    }

    @MainActor private func captureEntireViewport(_ caseID: String, region: String, identifier: String, app: XCUIApplication, remainingImages: inout Int) {
        let prefix = caseID + (region == "editor" ? "--editor" : "")
        let keyboardRequired = caseID.contains("--keyboard")
        let edge = identifier != "parity-scroll-note-editor"
        // At accessibility5 the 196pt editor contains 7,923pt of text. A 0.6
        // pan advances only 104pt after UIKit recognizes it, exhausting the
        // shared image budget. Use more of this small viewport while retaining
        // the same measured overlap, screenshot budget and actual-bottom rule.
        let forwardSpan = region == "editor" ? 0.88 : 0.6
        func measuredViewport() -> ParityMeasuredViewport {
            keyboardRequired ? parityStableViewport(identifier, in: app) : parityViewport(identifier, in: app)
        }
        var measured = measuredViewport()
        // Focus and lazy layout may start inside the content. Measure, then return
        // through real gestures to the top before claiming top coverage.
        for _ in 0..<60 {
            if measured.offset <= 1 { break }
            let previous = measured.offset
            parityDrag(measured.frame, downward: true, in: app, edge: edge)
            measured = measuredViewport()
            XCTAssertLessThan(measured.offset, previous - 0.5, "Cannot reach top: \(caseID)")
        }
        XCTAssertLessThanOrEqual(measured.offset, 1, "Top was not reached: \(caseID)")
        XCTAssertGreaterThan(remainingImages, 0)
        if keyboardRequired {
            parityAssertKeyboardVisible(in: app)
            if caseID.hasPrefix("now-note--") { parityAssertNoteActionsSeparated(in: app) }
        }
        attach(prefix + "--top", app: app, metrics: measured, region: region, probe: identifier)
        remainingImages -= 1
        var finished = measured.maxOffset <= 1
        var step = 0
        while !finished && remainingImages > 0 {
            step += 1
            let previous = measured
            // Even short overflowing pages need a real intermediate position.
            // Use a shorter first gesture, then verify its actual measured result.
            let distance = step == 1 ? min(measured.frame.height * forwardSpan, measured.maxOffset / 2) : nil
            parityDrag(measured.frame, downward: false, in: app, edge: edge, distance: distance, span: forwardSpan)
            measured = measuredViewport()
            // A focused editor can cause its outer scroll view to overshoot a
            // finger movement. Keep that original evidence, then use measured
            // reverse/forward pans to reach an overlapping position. A bounded
            // correction must succeed before any screenshot is called coverage.
            let coverageLimit = previous.frame.height * 0.9 + 1
            for correction in 0..<6 {
                let progress = measured.offset - previous.offset
                if progress > 0.5 && progress <= coverageLimit { break }
                // Reserve one image for the final measured position; diagnostic
                // captures consume the same 60-image budget as coverage images.
                if remainingImages <= 1 { break }
                attach(prefix + "--adjustment-\(step)-\(correction)", app: app,
                       metrics: measured, region: region, probe: identifier)
                remainingImages -= 1
                let target = min(previous.maxOffset, previous.offset + previous.frame.height * 0.55)
                let delta = measured.offset - target
                parityDrag(measured.frame, downward: delta > 0, in: app, edge: edge,
                           distance: max(24, abs(delta) + 10))
                measured = measuredViewport()
            }
            // Store failed geometry too; a capture command must not silently
            // turn an unmeasured gap into successful visual coverage.
            if keyboardRequired {
                parityAssertKeyboardVisible(in: app)
                if caseID.hasPrefix("now-note--") { parityAssertNoteActionsSeparated(in: app) }
            }
            attach(prefix + "--scroll-\(step)", app: app, metrics: measured, region: region, probe: identifier)
            remainingImages -= 1
            XCTAssertEqual(measured.frame.height, previous.frame.height, accuracy: 1, "Viewport changed during coverage: \(caseID)")
            XCTAssertGreaterThan(measured.offset, previous.offset + 0.5, "Scroll made no progress: \(caseID)")
            XCTAssertLessThanOrEqual(measured.offset - previous.offset, previous.frame.height * 0.9 + 1,
                                     "Uninspected gap between screenshots: \(caseID)")
            finished = measured.offset >= measured.maxOffset - 1
        }
        XCTAssertTrue(finished, "60-image bound reached without actual bottom: \(caseID)")
        if caseID.hasPrefix("home--words") { XCTAssertTrue(app.buttons["confirm-words"].isHittable) }
        if caseID.hasPrefix("diary--long") { XCTAssertTrue(app.buttons["edit-diary"].isHittable) }
        if caseID.hasPrefix("detail--transcript-expanded") {
            XCTAssertTrue(app.staticTexts["米洛：那一刻，是什么让你记住了它？"].isHittable)
        }
        if caseID.hasPrefix("card--") {
            XCTAssertTrue(app.buttons["card-template-planet-letter"].isHittable)
            XCTAssertTrue(app.buttons["card-template-orbit-theatre"].isHittable)
        }
    }

    @MainActor private func attach(_ name: String, app: XCUIApplication, metrics: ParityMeasuredViewport? = nil, region: String = "page", probe: String? = nil) {
        let screenshot = app.screenshot()
        // A saved image must describe the same scroll position as its receipt.
        // Check after screenshot acquisition as well; never pair stale geometry
        // with a later image or silently accept an uninspected jump.
        let afterScreenshot: ParityMeasuredViewport?
        if metrics != nil, let probe, name.contains("--keyboard") {
            afterScreenshot = parityViewport(probe, in: app)
        } else { afterScreenshot = nil }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "--accessibility"; tree.lifetime = .keepAlways; add(tree)
        if let metrics {
            let evidence: [String: Any] = ["region": region, "probe": probe ?? "", "raw": metrics.raw, "scrollOffset": metrics.offset,
                "totalContentHeight": metrics.contentHeight, "viewportHeight": metrics.frame.height,
                "maxScrollOffset": metrics.maxOffset,
                "geometryBracketChecked": afterScreenshot != nil,
                "geometryBracketMatched": afterScreenshot.map { paritySameViewport(metrics, $0) } ?? true,
                "afterScreenshotRaw": afterScreenshot?.raw ?? metrics.raw,
                "visibleFrame": ["x": metrics.frame.minX, "y": metrics.frame.minY,
                                 "width": metrics.frame.width, "height": metrics.frame.height]]
            let data = try! JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys, .prettyPrinted])
            let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            receipt.name = name + "--geometry"; receipt.lifetime = .keepAlways; add(receipt)
        }
        // Retain the failed image and both measurements before XCTest aborts.
        if let metrics, let afterScreenshot {
            XCTAssertTrue(paritySameViewport(metrics, afterScreenshot),
                          "Geometry changed while acquiring screenshot: \(name)")
        }
    }
}
