import XCTest

struct ParityMeasuredViewport {
    let raw: [String: Double]
    let frame: CGRect
    let contentHeight: Double
    let offset: Double
    var maxOffset: Double { max(0, contentHeight - frame.height) }
}

@MainActor func parityProbe(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}

@MainActor func parityValues(_ identifier: String, in app: XCUIApplication) -> [String: Double] {
    let probe = parityProbe(identifier, in: app)
    XCTAssertTrue(probe.exists || probe.waitForExistence(timeout: 5), "Missing live geometry: \(identifier)")
    for _ in 0..<25 {
        if let value = probe.value as? String, let data = value.data(using: .utf8),
           let values = try? JSONDecoder().decode([String: Double].self, from: data), !values.isEmpty {
            return values
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    XCTFail("No actual geometry was published by \(identifier): \(probe.value ?? "nil")")
    return [:]
}

private func measuredRect(_ values: [String: Double]) -> CGRect {
    CGRect(x: values["frameX"] ?? 0, y: values["frameY"] ?? 0,
           width: values["frameWidth"] ?? 0, height: values["frameHeight"] ?? 0)
}

@MainActor func parityViewport(_ identifier: String, in app: XCUIApplication) -> ParityMeasuredViewport {
    let raw = parityValues(identifier, in: app)
    let full = measuredRect(raw)
    let topInset = max(0, raw["insetTop"] ?? 0)
    let bottomInset = max(0, raw["insetBottom"] ?? 0)
    // SwiftUI's container/frame already excludes its contentInsets; its
    // visibleRect reports the larger underlying scroll bounds. UIKit bounds
    // are different and still need adjustedContentInset removed.
    let isTextView = raw["isUIKitTextView"] == 1
    var frame = isTextView
        ? CGRect(x: full.minX, y: full.minY + topInset,
                 width: full.width, height: max(0, full.height - topInset - bottomInset))
        : full
    frame = frame.intersection(measuredRect(parityValues("parity-viewport", in: app)))
    if identifier == "parity-scroll-note-editor" {
        let outer = parityValues("parity-scroll-journey-now-note", in: app)
        frame = frame.intersection(measuredRect(outer))
    }
    let keyboard = app.keyboards.firstMatch
    if keyboard.exists, keyboard.frame.minY > frame.minY {
        frame.size.height = min(frame.height, keyboard.frame.minY - frame.minY)
    }
    // Fixed actions can have frames inside a ScrollView's large AX bounds.
    // Public scroll insets usually already exclude them; use the actual control
    // as an additional upper bound rather than trusting AX scroll bounds.
    for id in ["save-now", "save-past", "save-card", "card-home", "open-card"] {
        let button = app.buttons[id]
        if button.exists, button.isHittable, button.frame.minY > frame.minY,
           button.frame.minY < frame.maxY {
            frame.size.height = button.frame.minY - frame.minY
        }
    }
    XCTAssertFalse(frame.isNull, identifier)
    XCTAssertGreaterThan(frame.height, 30, "No usable scroll viewport: \(identifier)")
    XCTAssertLessThanOrEqual(raw["contentWidth"] ?? 0, (raw["containerWidth"] ?? full.width) + 1,
                             "Horizontal content escapes the viewport: \(identifier)")
    XCTAssertLessThanOrEqual(raw["contentWidth"] ?? 0, frame.width + 1,
                             "Content is clipped by the safe horizontal viewport: \(identifier)")
    let externalTopClip = frame.minY - full.minY - (isTextView ? topInset : 0)
    let offset = (raw["offsetY"] ?? 0) + topInset + externalTopClip
    return ParityMeasuredViewport(raw: raw, frame: frame,
                                  contentHeight: raw["contentHeight"] ?? 0, offset: max(0, offset))
}

@MainActor func parityDrag(_ frame: CGRect, downward: Bool, in app: XCUIApplication, edge: Bool,
                          distance: Double? = nil, span: Double = 0.6) {
    let x = edge ? frame.minX + min(22, frame.width * 0.06) : frame.midX
    // Larger editor pans still begin/end inside its visible frame. The 0.88
    // span leaves 6% at each edge and stays below the 0.9 coverage threshold;
    // measured offsets, including pan recognition loss, remain authoritative.
    let margin = frame.height * min(0.15, (1 - span) / 2)
    let startY = downward ? frame.minY + margin : frame.maxY - margin
    let movement = min(frame.height * span, max(12, distance ?? frame.height * span))
    let endY = startY + (downward ? movement : -movement)
    let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: startY))
    let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: endY))
    parityPan(from: start, to: end, distance: movement)
    Thread.sleep(forTimeInterval: 0.25)
}

/// Bound the touch movement to roughly 0.6 seconds instead of holding a slow
/// multi-second gesture on long pages. The short stationary release prevents
/// a flick; actual offsets (never requested distances) still prove coverage.
@MainActor private func parityPan(from start: XCUICoordinate, to end: XCUICoordinate, distance: Double) {
    let velocity = XCUIGestureVelocity(rawValue: max(120, abs(distance) / 0.6))
    start.press(forDuration: 0.01, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0.15)
}

@MainActor func parityAlignEditor(in app: XCUIApplication) {
    for _ in 0..<10 {
        let outer = parityViewport("parity-scroll-journey-now-note", in: app)
        let inner = measuredRect(parityValues("parity-scroll-note-editor", in: app))
        if outer.frame.insetBy(dx: -1, dy: -1).contains(inner) { return }
        let delta = inner.minY < outer.frame.minY
            ? outer.frame.minY - inner.minY + 2
            : outer.frame.maxY - inner.maxY - 2
        // A drag spends its first points crossing UIKit's pan threshold. A
        // residual ten-point correction never moves content; include that cost.
        let requested = (delta < 0 ? -1.0 : 1.0) * max(24, abs(delta) + 12)
        let move = max(-outer.frame.height * 0.65, min(outer.frame.height * 0.65, requested))
        let startY = move > 0 ? outer.frame.minY + 10 : outer.frame.maxY - 10
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: outer.frame.minX + 12, dy: startY))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: outer.frame.minX + 12, dy: startY + move))
        parityPan(from: start, to: end, distance: move)
        Thread.sleep(forTimeInterval: 0.25)
    }
    XCTFail("The complete editor could not be aligned inside the measured outer viewport")
}

@MainActor func parityAssertKeyboardVisible(in app: XCUIApplication) {
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.exists || keyboard.waitForExistence(timeout: 5))
    let visible = keyboard.frame.intersection(app.frame)
    XCTAssertFalse(visible.isNull, "The software keyboard must actually be on screen")
    XCTAssertGreaterThan(visible.height, 80, "An offscreen keyboard accessibility node is not keyboard evidence")
}

/// Compare actual content/viewport geometry, including keyboard-induced insets.
/// Caret blinking or its presentation does not define scroll coverage.
func paritySameViewport(_ first: ParityMeasuredViewport, _ second: ParityMeasuredViewport) -> Bool {
    let keys = ["offsetX", "offsetY", "contentWidth", "contentHeight", "containerWidth", "containerHeight",
                "insetTop", "insetBottom", "frameX", "frameY", "frameWidth", "frameHeight"]
    return keys.allSatisfy { abs((first.raw[$0] ?? 0) - (second.raw[$0] ?? 0)) <= 0.5 }
        && abs(first.offset - second.offset) <= 0.5
        && abs(first.frame.minY - second.frame.minY) <= 0.5
        && abs(first.frame.height - second.frame.height) <= 0.5
}

/// AX queries used to calculate the visible frame take time. A sample read
/// before those queries can precede focus/keyboard auto-scroll by a whole page.
/// Require two consecutive matching measurements instead of trusting that sample.
@MainActor func parityStableViewport(_ identifier: String, in app: XCUIApplication) -> ParityMeasuredViewport {
    var previous = parityViewport(identifier, in: app)
    var matches = 0
    for _ in 0..<8 {
        Thread.sleep(forTimeInterval: 0.15)
        let current = parityViewport(identifier, in: app)
        matches = paritySameViewport(previous, current) ? matches + 1 : 0
        if matches >= 2 { return current }
        previous = current
    }
    XCTFail("Focus/keyboard geometry never settled: \(identifier)")
    return previous
}

@MainActor func parityAssertNoteActionsSeparated(in app: XCUIApplication) {
    let done = app.buttons["note-editor-done"]
    let save = app.buttons["save-now"]
    XCTAssertTrue(done.exists && done.isHittable)
    XCTAssertTrue(save.exists && save.isHittable)
    XCTAssertGreaterThanOrEqual(done.frame.height, 44)
    XCTAssertLessThanOrEqual(done.frame.maxY, save.frame.minY,
                            "Complete editing and save must occupy separate reserved rows")
    let intersection = done.frame.intersection(save.frame)
    XCTAssertTrue(intersection.isNull || intersection.height <= 0,
                  "The keyboard completion action must not cover the save button")
}
