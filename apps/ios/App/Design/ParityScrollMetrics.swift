import SwiftUI
import UIKit

extension View {
    /// Public runtime geometry is exposed only to UUID-isolated screenshot tests.
    /// This modifier never changes offsets or drives the production scroll view.
    @ViewBuilder func parityScrollMetrics(_ identifier: String) -> some View {
        #if DEBUG
        if ParityFixture.caseID != nil, #available(iOS 18.0, *) {
            modifier(ParityScrollProbe(identifier: identifier))
        } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder func parityTextMetrics(_ identifier: String) -> some View {
        #if DEBUG
        if ParityFixture.caseID != nil {
            overlay(alignment: .topLeading) {
                ParityTextProbe(identifier: identifier)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("parity-scroll-" + identifier)
                    .allowsHitTesting(false)
            }
        } else { self }
        #else
        self
        #endif
    }
}

#if DEBUG
/// UITextView owns an independent scroll region. Observe its public geometry,
/// including the insertion point, without reading text or changing selection.
private struct ParityTextProbe: UIViewRepresentable {
    let identifier: String
    func makeUIView(context: Context) -> TextGeometryObserver {
        let view = TextGeometryObserver()
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "parity-scroll-" + identifier
        view.accessibilityLabel = "Text editor geometry"
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ uiView: TextGeometryObserver, context: Context) { uiView.sample() }
    static func dismantleUIView(_ uiView: TextGeometryObserver, coordinator: ()) { uiView.stop() }
}

private final class TextGeometryObserver: UIView {
    private var timer: Timer?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        stop()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() { timer?.invalidate(); timer = nil }
    func sample() {
        accessibilityValue = "pending"
        guard let window, bounds.width > 0, bounds.height > 0 else { return }
        let probe = convert(bounds, to: window)
        func editors(in view: UIView) -> [UITextView] {
            if let editor = view as? UITextView { return [editor] }
            return view.subviews.flatMap { editors(in: $0) }
        }
        func visible(_ view: UIView) -> Bool {
            var node: UIView? = view
            while let current = node {
                if current.isHidden || current.alpha <= 0 { return false }
                node = current.superview
            }
            return view.convert(view.bounds, to: window).intersects(probe)
        }
        guard let editor = editors(in: window).filter(visible)
            .max(by: { left, right in
                let a = left.convert(left.bounds, to: window).intersection(probe)
                let b = right.convert(right.bounds, to: window).intersection(probe)
                return a.width * a.height < b.width * b.height
            }) else { return }
        let frame = editor.convert(editor.bounds, to: window)
        guard frame.intersects(probe) else { return }
        let insets = editor.adjustedContentInset
        var values: [String: Double] = [
            "isUIKitTextView": 1,
            "isFirstResponder": editor.isFirstResponder ? 1 : 0,
            "offsetX": editor.contentOffset.x, "offsetY": editor.contentOffset.y,
            "contentWidth": editor.contentSize.width, "contentHeight": editor.contentSize.height,
            "containerHeight": editor.bounds.height, "containerWidth": editor.bounds.width,
            "insetTop": insets.top, "insetBottom": insets.bottom,
            "frameX": frame.minX, "frameY": frame.minY,
            "frameWidth": frame.width, "frameHeight": frame.height
        ]
        if let selection = editor.selectedTextRange {
            let caret = editor.convert(editor.caretRect(for: selection.end), to: window)
            values["caretY"] = caret.minY; values["caretHeight"] = caret.height
            values["caretX"] = caret.minX; values["caretWidth"] = caret.width
            values["selectionIsEmpty"] = selection.isEmpty ? 1 : 0
        }
        guard values.values.allSatisfy(\.isFinite),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        accessibilityValue = json
    }
}

/// UIKit owns this leaf so parent SwiftUI identifiers cannot replace its identity.
private struct ParityMetricLabel: UIViewRepresentable {
    let identifier: String
    let value: String
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isAccessibilityElement = true
        view.isUserInteractionEnabled = false
        view.accessibilityLabel = "Scroll geometry"
        view.accessibilityIdentifier = identifier
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { view.accessibilityValue = value }
}

@available(iOS 18.0, *)
private struct ParityScrollProbe: ViewModifier {
    let identifier: String
    @State private var sample: ParityScrollSample?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ParityScrollSample.self) { ParityScrollSample($0) } action: { _, value in
                sample = value
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    ParityMetricLabel(identifier: "parity-scroll-" + identifier,
                                      value: sample?.json(frame: geometry.frame(in: .global)) ?? "pending")
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                }.allowsHitTesting(false)
            }
    }
}

@available(iOS 18.0, *)
private struct ParityScrollSample: Equatable {
    let offset: CGPoint
    let size: CGSize
    let container: CGSize
    let insets: EdgeInsets
    let visible: CGRect
    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset
        size = geometry.contentSize
        container = geometry.containerSize
        insets = geometry.contentInsets
        visible = geometry.visibleRect
    }
    func json(frame: CGRect) -> String {
        let values: [String: Double] = [
            "isUIKitTextView": 0,
            "offsetX": offset.x, "offsetY": offset.y,
            "contentWidth": size.width, "contentHeight": size.height,
            "containerHeight": container.height, "containerWidth": container.width,
            "insetTop": insets.top, "insetBottom": insets.bottom,
            "visibleX": visible.minX, "visibleWidth": visible.width,
            "visibleY": visible.minY, "visibleHeight": visible.height,
            "frameX": frame.minX, "frameY": frame.minY,
            "frameWidth": frame.width, "frameHeight": frame.height
        ]
        guard values.values.allSatisfy(\.isFinite),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "invalid" }
        return result
    }
}
#endif
