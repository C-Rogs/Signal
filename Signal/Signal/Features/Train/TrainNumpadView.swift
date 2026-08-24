import SwiftUI

struct TrainNumpadView: View {
    @Binding var text: String
    let allowsDecimal: Bool
    var maxLength: Int?
    var placeholder: String = "0"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 16) {
            Text(displayLine)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color("TextPrimary"))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("numpadDisplay")

            LazyVGrid(columns: columns, spacing: 10) {
                numpadKey("7") { applyDigit("7") }
                numpadKey("8") { applyDigit("8") }
                numpadKey("9") { applyDigit("9") }
                numpadKey("4") { applyDigit("4") }
                numpadKey("5") { applyDigit("5") }
                numpadKey("6") { applyDigit("6") }
                numpadKey("1") { applyDigit("1") }
                numpadKey("2") { applyDigit("2") }
                numpadKey("3") { applyDigit("3") }

                if allowsDecimal {
                    numpadKey(".") { applyDecimal() }
                } else {
                    Color.clear.frame(height: 52)
                }

                numpadKey("0") { applyDigit("0") }

                Button {
                    text = TrainNumpadLogic.backspace(text)
                } label: {
                    Image(systemName: "delete.backward")
                        .font(.title2.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(keyBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Backspace")
                .accessibilityIdentifier("numpadBackspace")
            }
            .padding(.horizontal, 16)
        }
    }

    private var displayLine: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }

    private var keyBackground: Color {
        Color("TextSecondary").opacity(0.12)
    }

    private func numpadKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title.weight(.medium))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(keyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("numpadKey-\(label)")
    }

    private func applyDigit(_ digit: String) {
        guard let character = digit.first,
              let updated = TrainNumpadLogic.appendDigit(character, to: text, allowsDecimal: allowsDecimal, maxLength: maxLength)
        else { return }
        text = updated
    }

    private func applyDecimal() {
        guard allowsDecimal,
              let updated = TrainNumpadLogic.appendDecimal(to: text, maxLength: maxLength)
        else { return }
        text = updated
    }
}
