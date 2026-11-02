import SwiftUI
import UIKit

/// Keeps the native editor's text, selection and undo stack alive across draft
/// persistence updates. Only genuine external replacements assign `text` again.
struct MiloNoteEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MiloCaretTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let editor = MiloCaretTextView(frame: .zero, textContainer: container)
        editor.delegate = context.coordinator
        editor.backgroundColor = .clear
        editor.textColor = UIColor(MiloTheme.ink)
        editor.tintColor = UIColor(MiloTheme.accent)
        editor.font = preferredFont
        editor.adjustsFontForContentSizeCategory = true
        editor.isScrollEnabled = true
        editor.alwaysBounceVertical = false
        editor.keyboardDismissMode = .none
        // SwiftUI already reserves the keyboard and bottom action bar.
        editor.contentInsetAdjustmentBehavior = .never
        editor.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        editor.textContainer.lineFragmentPadding = 5
        editor.accessibilityIdentifier = "note-input"
        editor.accessibilityLabel = "此刻的感受（选填）"
        editor.text = text
        return editor
    }

    func updateUIView(_ editor: MiloCaretTextView, context: Context) {
        context.coordinator.parent = self
        let font = preferredFont
        if editor.font != font {
            editor.font = font
            if editor.isFirstResponder { editor.requestCaretReveal() }
        }
        if editor.text != text {
            let selection = editor.selectedRange
            editor.text = text
            let count = (text as NSString).length
            let location = min(selection.location, count)
            editor.selectedRange = NSRange(location: location, length: min(selection.length, count - location))
            if editor.isFirstResponder { editor.requestCaretReveal() }
        }
        if isFocused, !editor.isFirstResponder, editor.window != nil {
            editor.becomeFirstResponder()
        } else if !isFocused, editor.isFirstResponder {
            editor.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ editor: MiloCaretTextView, coordinator: Coordinator) {
        editor.delegate = nil
    }

    private var preferredFont: UIFont {
        // SwiftUI's explicit accessibility size (including preview/fixture
        // environments) must reach UIKit; do not cap it at a smaller category.
        let category: UIContentSizeCategory
        switch dynamicTypeSize {
        case .xSmall: category = .extraSmall
        case .small: category = .small
        case .medium: category = .medium
        case .large: category = .large
        case .xLarge: category = .extraLarge
        case .xxLarge: category = .extraExtraLarge
        case .xxxLarge: category = .extraExtraExtraLarge
        case .accessibility1: category = .accessibilityMedium
        case .accessibility2: category = .accessibilityLarge
        case .accessibility3: category = .accessibilityExtraLarge
        case .accessibility4: category = .accessibilityExtraExtraLarge
        case .accessibility5: category = .accessibilityExtraExtraExtraLarge
        @unknown default: category = .large
        }
        return UIFont.preferredFont(forTextStyle: .body,
                                    compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MiloNoteEditor
        init(_ parent: MiloNoteEditor) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
            (textView as? MiloCaretTextView)?.requestCaretReveal()
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text { parent.text = textView.text }
            (textView as? MiloCaretTextView)?.requestCaretReveal()
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? MiloCaretTextView)?.requestCaretReveal()
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            (scrollView as? MiloCaretTextView)?.cancelCaretReveal()
        }
    }
}

/// Finish native text layout before exposing its insertion point. SwiftUI's
/// changing keyboard proposal must not leave a long-text caret above the editor.
final class MiloCaretTextView: UITextView {
    private var needsCaretReveal = false
    private var lastViewportSize = CGSize.zero
    private var revealingCaret = false

    func requestCaretReveal() {
        guard isFirstResponder, !isTracking, !isDragging, !isDecelerating else { return }
        needsCaretReveal = true
        setNeedsLayout()
    }
    func cancelCaretReveal() { needsCaretReveal = false }

    override func layoutSubviews() {
        let resized = bounds.size != lastViewportSize
        lastViewportSize = bounds.size
        super.layoutSubviews()
        guard !revealingCaret else { return }
        if resized, isFirstResponder { needsCaretReveal = true }
        guard needsCaretReveal else { return }
        needsCaretReveal = false
        guard isFirstResponder, window != nil, bounds.height > 0,
              !isTracking, !isDragging, !isDecelerating,
              let selection = selectedTextRange, selection.isEmpty else { return }
        revealingCaret = true
        defer { revealingCaret = false }
        layoutManager.ensureLayout(for: textContainer)
        // UIKit reveals the selected insertion range first; then use the actual
        // laid-out caret and viewport to remove any remaining clipped line.
        scrollRangeToVisible(selectedRange)
        let caret = caretRect(for: selection.end)
        guard !caret.isNull, !caret.isInfinite, caret.height > 0 else { return }
        let inset = adjustedContentInset
        let visibleTop = contentOffset.y + inset.top
        let visibleBottom = contentOffset.y + bounds.height - inset.bottom
        let margin: CGFloat = 4
        var y = contentOffset.y
        if caret.minY < visibleTop + margin {
            y = caret.minY - inset.top - margin
        } else if caret.maxY > visibleBottom - margin {
            y = caret.maxY - bounds.height + inset.bottom + margin
        }
        let maximum = max(-inset.top, contentSize.height - bounds.height + inset.bottom)
        y = min(maximum, max(-inset.top, y))
        if abs(y - contentOffset.y) > 0.5 {
            setContentOffset(CGPoint(x: contentOffset.x, y: y), animated: false)
        }
    }
}
