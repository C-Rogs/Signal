import Foundation

enum RFC4180CSVParser {
    static func parseRecords(from data: Data) throws -> [[String]] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw CSVParseError.invalidEncoding
        }
        return try parseRecords(from: text)
    }

    static func parseRecords(from text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var index = text.startIndex
        var inQuotes = false

        func endField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func endRow() {
            endField()
            if !currentRow.isEmpty || !currentField.isEmpty {
                rows.append(currentRow)
            }
            currentRow = []
        }

        while index < text.endIndex {
            let character = text[index]

            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        currentField.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
                index = text.index(after: index)
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
                index = text.index(after: index)
            case ",":
                endField()
                index = text.index(after: index)
            case "\r":
                index = text.index(after: index)
                if index < text.endIndex, text[index] == "\n" {
                    index = text.index(after: index)
                }
                endRow()
            case "\n":
                index = text.index(after: index)
                endRow()
            default:
                currentField.append(character)
                index = text.index(after: index)
            }
        }

        if inQuotes {
            throw CSVParseError.unterminatedQuote
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            endRow()
        }

        return rows
    }
}

enum CSVParseError: Error, Sendable {
    case invalidEncoding
    case unterminatedQuote
    case emptyFile
}
