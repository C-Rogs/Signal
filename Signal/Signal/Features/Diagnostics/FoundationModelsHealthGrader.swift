import Foundation

enum FoundationModelsHealthVerdict: String, Sendable, Equatable, Codable {
    case pass = "PASS"
    case fail = "FAIL"
    case review = "REVIEW"
    case skip = "SKIP"
}

struct FoundationModelsHealthProbeOutcome: Sendable, Equatable, Codable {
    let probeID: String
    let label: String
    let verdict: FoundationModelsHealthVerdict
    let detail: String?
    let latencyMs: Int?
    let errorMessage: String?

    var succeeded: Bool { verdict == .pass }
}

enum FoundationModelsHealthGrader {
    static func grade(
        definition: FoundationModelsHealthProbeDefinition,
        execution: FoundationModelsHealthProbeExecution
    ) -> FoundationModelsHealthProbeOutcome {
        if let error = execution.errorMessage {
            if definition.kind == .availability {
                return outcome(
                    definition: definition,
                    execution: execution,
                    verdict: .skip,
                    detail: "Model unavailable",
                    errorMessage: error
                )
            }
            return outcome(
                definition: definition,
                execution: execution,
                verdict: .fail,
                detail: nil,
                errorMessage: error
            )
        }

        switch definition.kind {
        case .availability:
            let ready = execution.boolValue == true
            return outcome(
                definition: definition,
                execution: execution,
                verdict: ready ? .pass : .skip,
                detail: execution.detail,
                errorMessage: ready ? nil : execution.detail
            )

        case .minimalGenerate:
            let text = execution.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return outcome(
                definition: definition,
                execution: execution,
                verdict: text.isEmpty ? .fail : .pass,
                detail: text.isEmpty ? "empty response" : "chars=\(text.count)"
            )

        case .structuredClassify(let expectedAlcoholLikely, let eventTitle):
            let alcoholLikely = execution.boolValue == true
            if expectedAlcoholLikely {
                let verdict: FoundationModelsHealthVerdict = alcoholLikely ? .pass : .review
                return outcome(
                    definition: definition,
                    execution: execution,
                    verdict: verdict,
                    detail: "title=\(eventTitle) alcoholLikely=\(alcoholLikely)"
                )
            }
            let verdict: FoundationModelsHealthVerdict = alcoholLikely ? .fail : .pass
            return outcome(
                definition: definition,
                execution: execution,
                verdict: verdict,
                detail: "title=\(eventTitle) alcoholLikely=\(alcoholLikely)"
            )

        case .coachStream:
            let count = execution.textValue?.count ?? 0
            let verdict: FoundationModelsHealthVerdict
            if count >= FoundationModelsHealthCatalog.coachStreamMinCharacters {
                verdict = .pass
            } else if count > 0 {
                verdict = .review
            } else {
                verdict = .fail
            }
            return outcome(
                definition: definition,
                execution: execution,
                verdict: verdict,
                detail: "streamChars=\(count)"
            )

        case .gateSerial:
            let first = execution.boolValue == true
            let secondBusy = execution.secondaryBoolValue == false
            let verdict: FoundationModelsHealthVerdict = (first && secondBusy) ? .pass : .fail
            return outcome(
                definition: definition,
                execution: execution,
                verdict: verdict,
                detail: "firstAcquire=\(first) secondAcquireBlocked=\(secondBusy)"
            )

        case .toolRoundtrip:
            let text = execution.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return outcome(
                definition: definition,
                execution: execution,
                verdict: text.isEmpty ? .review : .pass,
                detail: text.isEmpty ? "empty tool response" : "chars=\(text.count)"
            )
        }
    }

    static func summarize(_ outcomes: [FoundationModelsHealthProbeOutcome]) -> String {
        let pass = outcomes.filter { $0.verdict == .pass }.count
        let fail = outcomes.filter { $0.verdict == .fail }.count
        let review = outcomes.filter { $0.verdict == .review }.count
        let skip = outcomes.filter { $0.verdict == .skip }.count
        return "\(pass) PASS, \(fail) FAIL, \(review) REVIEW, \(skip) SKIP"
    }

    static func suitePassed(_ outcomes: [FoundationModelsHealthProbeOutcome]) -> Bool {
        outcomes.allSatisfy { $0.verdict == .pass || $0.verdict == .review || $0.verdict == .skip }
            && outcomes.contains { $0.verdict == .pass }
    }

    private static func outcome(
        definition: FoundationModelsHealthProbeDefinition,
        execution: FoundationModelsHealthProbeExecution,
        verdict: FoundationModelsHealthVerdict,
        detail: String?,
        errorMessage: String? = nil
    ) -> FoundationModelsHealthProbeOutcome {
        FoundationModelsHealthProbeOutcome(
            probeID: definition.id,
            label: definition.label,
            verdict: verdict,
            detail: detail ?? execution.detail,
            latencyMs: execution.latencyMs,
            errorMessage: errorMessage
        )
    }
}

struct FoundationModelsHealthProbeExecution: Sendable, Equatable {
    let boolValue: Bool?
    let secondaryBoolValue: Bool?
    let textValue: String?
    let detail: String?
    let latencyMs: Int?
    let errorMessage: String?

    init(
        boolValue: Bool? = nil,
        secondaryBoolValue: Bool? = nil,
        textValue: String? = nil,
        detail: String? = nil,
        latencyMs: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.boolValue = boolValue
        self.secondaryBoolValue = secondaryBoolValue
        self.textValue = textValue
        self.detail = detail
        self.latencyMs = latencyMs
        self.errorMessage = errorMessage
    }
}
