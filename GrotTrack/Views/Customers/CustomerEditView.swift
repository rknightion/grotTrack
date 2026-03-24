import SwiftUI

struct CustomerEditView: View {
    enum Mode {
        case add
        case edit(Customer)
    }

    let mode: Mode
    let onSave: (String, [String], String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var keywordsText: String = ""
    @State private var selectedColor: String = "blue"
    @State private var isActive: Bool = true

    private let presetColors = [
        "blue", "red", "green", "purple", "orange",
        "pink", "teal", "indigo", "mint", "brown"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Customer Name", text: $name)

                Section("Keywords") {
                    TextField("Enter keywords, comma separated", text: $keywordsText)
                    Text("Keywords are used to auto-match activities to this customer")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !parsedKeywords.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(parsedKeywords, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 5), spacing: 8) {
                        ForEach(presetColors, id: \.self) { colorName in
                            Circle()
                                .fill(colorForName(colorName))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle().stroke(Color.primary, lineWidth: selectedColor == colorName ? 2 : 0)
                                )
                                .onTapGesture { selectedColor = colorName }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if case .edit = mode {
                    Toggle("Active", isOn: $isActive)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    onSave(name, parsedKeywords, selectedColor)
                    if case .edit(let customer) = mode {
                        customer.isActive = isActive
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 350, minHeight: 300)
        .onAppear {
            if case .edit(let customer) = mode {
                name = customer.name
                keywordsText = customer.keywords.joined(separator: ", ")
                selectedColor = customer.color
                isActive = customer.isActive
            }
        }
    }

    private var parsedKeywords: [String] {
        keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "red": .red
        case "green": .green
        case "purple": .purple
        case "orange": .orange
        case "pink": .pink
        case "teal": .teal
        case "indigo": .indigo
        case "mint": .mint
        case "brown": .brown
        default: .blue
        }
    }
}
