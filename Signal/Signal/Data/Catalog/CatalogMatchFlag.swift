import Foundation

enum CatalogMatchFlag: String, Codable, Sendable {
    case matched
    case unmatched
    case lowConfidence
}
