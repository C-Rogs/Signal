import Foundation

enum TrainNumpadLogic {
    static func appendDigit(_ digit: Character, to text: String, allowsDecimal: Bool, maxLength: Int? = nil) -> String? {
        guard digit.isNumber else { return nil }
        guard maxLength == nil || text.count < maxLength! else { return nil }
        return text + String(digit)
    }

    static func appendDecimal(to text: String, maxLength: Int? = nil) -> String? {
        guard !text.contains(".") else { return nil }
        guard maxLength == nil || text.count < maxLength! else { return nil }
        return text.isEmpty ? "0." : text + "."
    }

    static func backspace(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return String(text.dropLast())
    }

    static func clear() -> String {
        ""
    }
}
