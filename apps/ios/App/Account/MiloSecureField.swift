import SwiftUI

/// The visibility toggle never persists or logs the field contents.
struct MiloSecureField: View {
    let title: String
    @Binding var text: String
    let identifier: String
    let contentType: UITextContentType
    @State private var visible = false

    init(_ title: String, text: Binding<String>, identifier: String,
         contentType: UITextContentType = .password) {
        self.title = title; _text = text
        self.identifier = identifier; self.contentType = contentType
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if visible { TextField(title, text: $text) }
                else { SecureField(title, text: $text) }
            }.textContentType(contentType).textInputAutocapitalization(.never)
                .autocorrectionDisabled().accessibilityIdentifier(identifier)
            Button { visible.toggle() } label: {
                Image(systemName: visible ? "eye.slash" : "eye")
                    .foregroundStyle(MiloTheme.dim).frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(visible ? "隐藏密码" : "显示密码")
                .accessibilityIdentifier(identifier + "-visibility")
        }.miloAccountField()
            .onDisappear { visible = false }
    }
}
