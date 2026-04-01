import SwiftUI

struct AnnotationInputView: View {
    let contextAppName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Working in: \(contextAppName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("What are you working on?", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSave(text)
                }
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
        }
        .padding(12)
        .frame(width: 350)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
