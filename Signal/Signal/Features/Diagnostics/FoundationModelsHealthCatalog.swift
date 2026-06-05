import Foundation

enum FoundationModelsHealthProbeKind: Sendable, Equatable {
    case availability
    case minimalGenerate
    case structuredClassify(expectedAlcoholLikely: Bool, eventTitle: String)
    case coachStream
    case gateSerial
    case toolRoundtrip
}

struct FoundationModelsHealthProbeDefinition: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let kind: FoundationModelsHealthProbeKind
    let timeoutSeconds: TimeInterval
}

enum FoundationModelsHealthCatalog {
    static let coachStreamMinCharacters = 3
    static let suiteTimeoutSeconds: TimeInterval = 120

    static let all: [FoundationModelsHealthProbeDefinition] = [
        FoundationModelsHealthProbeDefinition(
            id: "model_ready",
            label: "Model availability",
            kind: .availability,
            timeoutSeconds: 1
        ),
        FoundationModelsHealthProbeDefinition(
            id: "gate_serial",
            label: "Inference gate serialization",
            kind: .gateSerial,
            timeoutSeconds: 2
        ),
        FoundationModelsHealthProbeDefinition(
            id: "minimal_text",
            label: "Minimal text generation",
            kind: .minimalGenerate,
            timeoutSeconds: 30
        ),
        FoundationModelsHealthProbeDefinition(
            id: "structured_pub_night",
            label: "Structured classify (pub night)",
            kind: .structuredClassify(expectedAlcoholLikely: true, eventTitle: "pub night"),
            timeoutSeconds: 30
        ),
        FoundationModelsHealthProbeDefinition(
            id: "structured_dentist",
            label: "Structured classify (dentist)",
            kind: .structuredClassify(expectedAlcoholLikely: false, eventTitle: "Dentist"),
            timeoutSeconds: 30
        ),
        FoundationModelsHealthProbeDefinition(
            id: "coach_stream",
            label: "Coach streaming smoke",
            kind: .coachStream,
            timeoutSeconds: 45
        ),
        FoundationModelsHealthProbeDefinition(
            id: "tool_roundtrip",
            label: "Tool roundtrip smoke",
            kind: .toolRoundtrip,
            timeoutSeconds: 45
        ),
    ]

    static func definition(id: String) -> FoundationModelsHealthProbeDefinition? {
        all.first { $0.id == id }
    }
}
