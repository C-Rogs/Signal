import Foundation

enum CoachUATVerdict: String, Sendable, Equatable, Codable {
    case pass = "PASS"
    case fail = "FAIL"
    case review = "REVIEW"
    case limit = "LIMIT"
}

struct CoachUATContextSnapshot: Sendable, Equatable, Codable {
    let promptCharacters: Int
    let ragDayCount: Int
    let insightCount: Int
    let hasACWR: Bool
    let hasVolume: Bool
    let hasProteinShortfall: Bool
    let hasRecoveryScore: Bool
    let hasCalendarSection: Bool
    let contextExcerpt: String
}

struct CoachUATResult: Identifiable, Sendable, Equatable, Codable {
    let definitionID: String
    let label: String
    let query: String
    let category: CoachUATCategory
    let verdict: CoachUATVerdict
    let checkLabel: String
    let ratioLabel: String
    let responsePreview: String
    let contextSnapshot: CoachUATContextSnapshot
    let notes: [String]
    let errorMessage: String?
    let latencyMs: Int?

    var id: String { definitionID }
}

enum CoachUATGrader {
    static func grade(
        definition: CoachUATDefinition,
        response: String,
        context: CoachUATContextSnapshot,
        errorMessage: String?
    ) -> CoachUATResult {
        if let errorMessage, !errorMessage.isEmpty {
            return makeResult(
                definition: definition,
                response: response,
                context: context,
                verdict: .fail,
                passed: 0,
                total: definition.gradeRules.count,
                notes: ["error: \(errorMessage)"],
                errorMessage: errorMessage,
                latencyMs: nil
            )
        }

        var notes: [String] = []
        var passed = 0
        var failures = 0
        var reviews = 0

        for rule in definition.gradeRules {
            switch evaluate(rule: rule, response: response, context: context) {
            case .pass:
                passed += 1
            case .fail(let note):
                failures += 1
                notes.append(note)
            case .review(let note):
                reviews += 1
                notes.append("review: \(note)")
            }
        }

        let total = definition.gradeRules.count
        let verdict: CoachUATVerdict
        if failures > 0 {
            verdict = .fail
        } else if passed == total {
            verdict = .pass
        } else if reviews > 0 {
            verdict = .review
        } else {
            verdict = .fail
        }

        return makeResult(
            definition: definition,
            response: response,
            context: context,
            verdict: verdict,
            passed: passed,
            total: total,
            notes: notes,
            errorMessage: nil,
            latencyMs: nil
        )
    }

    private enum RuleOutcome {
        case pass
        case fail(String)
        case review(String)
    }

    private static func evaluate(
        rule: CoachUATGradeRule,
        response: String,
        context: CoachUATContextSnapshot
    ) -> RuleOutcome {
        let text = response.lowercased()

        switch rule {
        case .minLength(let chars):
            return response.count >= chars ? .pass : .fail("response too short (\(response.count) < \(chars))")

        case .noGenericPlatitudes:
            let banned = [
                "stay hydrated",
                "drink plenty of water",
                "remember to hydrate",
                "get plenty of rest",
                "listen to your body",
                "consistency is key",
                "trust the process",
            ]
            for phrase in banned {
                if text.contains(phrase) {
                    return .fail("generic platitude: \(phrase)")
                }
            }
            if text.contains("make sure you get enough sleep"), !context.contextExcerpt.lowercased().contains("sleep") {
                return .fail("unsolicited sleep reminder")
            }
            if text.contains("eat more protein"), !context.hasProteinShortfall {
                return .review("protein push without shortfall in context")
            }
            return .pass

        case .recoveryGrounded:
            let markers = ["recovery", "hrv", "readiness", "sleep", "rhr", "resting"]
            if markers.contains(where: { text.contains($0) }) {
                return .pass
            }
            if context.hasRecoveryScore {
                return .fail("recovery answer missing recovery/sleep/HRV grounding")
            }
            return .review("recovery markers absent; context may lack health data")

        case .trainingGrounded:
            let markers = ["acwr", "volume", "sets", "strain", "deload", "recovery", "legs", "train"]
            return markers.contains(where: { text.contains($0) })
                ? .pass
                : .fail("training answer not grounded in load/recovery")

        case .referencesACWR:
            if text.contains("acwr") || text.range(of: #"\b1\.\d{1,2}\b"#, options: .regularExpression) != nil {
                return .pass
            }
            if context.hasACWR {
                return .fail("ACWR in context but answer omits load ratio")
            }
            return .review("ACWR unavailable in context")

        case .referencesVolume:
            if text.contains("volume") || text.contains(" sets") || text.range(of: #"\b\d+\s*sets?\b"#, options: .regularExpression) != nil {
                return .pass
            }
            if context.hasVolume {
                return .fail("volume in context but answer omits set counts")
            }
            return .review("volume data sparse in context")

        case .scheduleGrounded:
            if text.contains("calendar") || text.contains("schedule") || text.contains("no events") || text.contains("nothing scheduled") {
                return .pass
            }
            if context.hasCalendarSection {
                return .review("schedule answer vague despite calendar context")
            }
            return .review("calendar access or events may be empty")

        case .exerciseHistoryGrounded:
            let markers = ["squat", "bench", "session", "kg", "×", "x", "e1rm", "no history", "no logged", "not found"]
            return markers.contains(where: { text.contains($0) })
                ? .pass
                : .review("exercise history may be empty on device")

        case .proteinWhenRelevant:
            if text.contains("protein") || text.contains("g ") || text.contains("gram") {
                return .pass
            }
            if context.hasProteinShortfall {
                return .fail("protein shortfall in context but answer silent")
            }
            return .review("protein target may be met or unavailable")

        case .defersClinical:
            if text.contains("doctor") || text.contains("physio") || text.contains("medical") || text.contains("clinician") {
                return .pass
            }
            if text.contains("you have") || text.contains("this is a") || text.contains("likely a tear") {
                return .fail("appears to diagnose")
            }
            return .fail("missing defer-to-clinician language")

        case .refusesOffTopic:
            if text.contains("focus on training") || text.contains("training and recovery") || text.contains("can't help") || text.contains("outside") {
                return .pass
            }
            return text.contains("election") || text.contains("president") || text.contains("vote")
                ? .fail("answered off-topic question")
                : .review("refusal wording unclear")

        case .proactiveSynthesis:
            let markerCount = [
                text.contains("recovery"),
                text.contains("acwr") || text.range(of: #"\b1\.\d{1,2}\b"#, options: .regularExpression) != nil,
                text.contains("volume") || text.contains(" sets"),
                context.insightCount > 0 && (text.contains("insight") || text.contains("flag") || text.contains("strain") || text.contains("deload")),
            ].filter { $0 }.count
            return markerCount >= 2 ? .pass : .review("proactive answer only covered one dimension")
        }
    }

    private static func makeResult(
        definition: CoachUATDefinition,
        response: String,
        context: CoachUATContextSnapshot,
        verdict: CoachUATVerdict,
        passed: Int,
        total: Int,
        notes: [String],
        errorMessage: String?,
        latencyMs: Int?
    ) -> CoachUATResult {
        CoachUATResult(
            definitionID: definition.id,
            label: definition.label,
            query: definition.query,
            category: definition.category,
            verdict: verdict,
            checkLabel: definition.checkLabel,
            ratioLabel: "\(passed)/\(total)",
            responsePreview: preview(response),
            contextSnapshot: context,
            notes: notes,
            errorMessage: errorMessage,
            latencyMs: latencyMs
        )
    }

    private static func preview(_ text: String) -> String {
        let collapsed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 280 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 280)
        return String(collapsed[..<end]) + "..."
    }

    static func summarize(_ results: [CoachUATResult]) -> String {
        let pass = results.filter { $0.verdict == .pass }.count
        let fail = results.filter { $0.verdict == .fail }.count
        let review = results.filter { $0.verdict == .review }.count
        let limit = results.filter { $0.verdict == .limit }.count
        return "\(pass) PASS, \(fail) FAIL, \(review) REVIEW, \(limit) LIMIT"
    }
}
