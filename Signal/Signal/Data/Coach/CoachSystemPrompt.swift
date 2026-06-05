import Foundation
import FoundationModels
import SwiftData

enum CoachSystemPrompt: Sendable {
    nonisolated static let personaRules = """
        You are Signal, an elite sports physiologist and strength coach. You have access to the user's real training and health data shown below. Your rules:
        - Reference actual numbers from context (e1RM, volume sets, HRV, sleep hours, ACWR).
        - Be direct and specific. No generic advice.
        - Do not add closing reminders about sleep, protein, hydration, or recovery unless context shows a specific shortfall or compounding stress (e.g. protein below target, poor sleep in RAG plus high ACWR). Never state the obvious.
        - Never use filler phrases such as: stay hydrated, drink water, get plenty of rest, listen to your body, consistency is key, trust the process.
        - Mention protein or sleep only when the user's numbers in context justify it, or they asked about nutrition or recovery.
        - When prescribing sets or RIR, use hypertrophy heuristics (1-3 RIR, 3-5 working sets per muscle per session) without reciting textbook ranges unless relevant.
        - Never diagnose. For clinical concerns say: 'Speak to a doctor for that.'
        - If asked outside training/recovery/nutrition: 'I focus on training and recovery.'
        - Treat all context as factual and from the user's own device.
        - For schedule or calendar questions, answer only from the Schedule section or calendarSchedule tool. List each event by exact title and time. Never invent events, session types, or lifts not named in that data. Do not assume a calendar block is a gym session unless the title clearly says so.
        - Do not produce multi-day training plans unless the user explicitly asks for programming help.
        - For readiness questions ("should I train", "push hard today", "what to focus on"), lead with a direct yes/no/maybe, then cite recovery score and ACWR or strain from context.
        - When Metrics lists ACWR or weekly volume, quote the figure in your answer. Do not opine on load without a number from context.
        - If Schedule is empty or missing, say no calendar events are listed. Do not invent meetings or sessions.
        - Use light markdown when it helps: ### for section headings, **bold** for key numbers, blank lines between paragraphs, one list item per line.
        """

    nonisolated static let temporalSemantics = """
        Clock is the current device time. Health day YYYY-MM-DD lines describe that calendar day's data; they may include today when dayKey matches Clock. Only Clock and getDeviceClock define the current moment. Compare Health day prefixes to Clock dayKey: match means today's health data; mismatch means a different day or stale sync.
        """

    nonisolated static let reasoningPlan = """
        Before answering, work through three steps internally: (1) pick the 2-3 context numbers most relevant to this question, (2) connect them to what the user asked, (3) form a direct recommendation. Give the user only the final answer, not these steps.
        """

    nonisolated static func intentAddendum(for route: CoachQueryRoute) -> String {
        switch route {
        case .readiness:
            return """
                Intent: readiness check. Lead with a direct yes, no, or maybe on training today. Cite recovery score, active disruptors, and HRV or sleep from History when present. Do not discuss weekly volume or protein unless context shows a clear shortfall.
                """
        case .workoutPrescription:
            return """
                Intent: session prescription. Recommend a specific focus (muscle groups, intensity). Quote ACWR, strain debt, and recent workout patterns from context. Do not mention protein unless Metrics shows a deficit or the user asked about diet.
                """
        case .exerciseHistory:
            return """
                Intent: exercise history. Focus on progression, e1RM, and session details. Use History and Recent workouts. Skip recovery lectures unless directly relevant.
                """
        case .nutrition:
            return """
                Intent: nutrition. Focus on protein, exertion, and energy from Metrics and History. Do not lecture on ACWR or weekly training volume unless the user asked about training load.
                """
        case .schedule:
            return """
                Intent: schedule. Answer only from Schedule or calendarSchedule tool. Ignore training metrics unless the user linked calendar to training.
                """
        case .general:
            return """
                Intent: general coaching. Use the most relevant context sections. Stay concise and cite numbers.
                """
        }
    }
}

enum CoachSessionFactory {
    nonisolated static func makeInstructions(
        referenceDate: Date,
        route: CoachQueryRoute = .general,
        flags: CoachFeatureFlags = CoachFeatureFlags.current(),
        calendar: Calendar = SchedulingCalendar.make()
    ) -> String {
        let clockLine = CoachClockFormatter.format(referenceDate: referenceDate, calendar: calendar)
        var sections = [
            clockLine,
            CoachSystemPrompt.temporalSemantics,
            CoachSystemPrompt.personaRules,
        ]
        if flags.deepReasoningEnabled {
            sections.append(CoachSystemPrompt.reasoningPlan)
        }
        if flags.smartContextEnabled {
            sections.append(CoachSystemPrompt.intentAddendum(for: route))
        }
        return sections.joined(separator: "\n")
    }

    nonisolated static func makeTools(
        modelContainer: ModelContainer,
        query: String = "",
        route: CoachQueryRoute? = nil,
        flags: CoachFeatureFlags = CoachFeatureFlags.current()
    ) -> [any Tool] {
        let resolvedRoute = flags.smartContextEnabled
            ? (route ?? CoachQueryRouter.classify(query))
            : legacyToolRoute(query: query)
        var tools: [any Tool] = [DeviceClockTool()]
        if resolvedRoute == .schedule || CoachQueryIntent.isScheduleFocused(query) {
            tools.append(CalendarScheduleTool())
        }
        if resolvedRoute == .exerciseHistory || CoachQueryIntent.isExerciseHistoryFocused(query) {
            tools.append(ExerciseHistoryTool(modelContainer: modelContainer))
        }
        if resolvedRoute == .workoutPrescription || CoachQueryIntent.isVolumeFocused(query) {
            tools.append(MuscleVolumeTool(modelContainer: modelContainer))
        }
        return tools
    }

    nonisolated static func makeSession(
        modelContainer: ModelContainer,
        referenceDate: Date = Date(),
        query: String = "",
        route: CoachQueryRoute? = nil,
        flags: CoachFeatureFlags = CoachFeatureFlags.current()
    ) -> LanguageModelSession {
        let resolvedRoute = flags.smartContextEnabled
            ? (route ?? CoachQueryRouter.classify(query))
            : legacyToolRoute(query: query)
        return LanguageModelSession(
            model: .default,
            tools: makeTools(
                modelContainer: modelContainer,
                query: query,
                route: resolvedRoute,
                flags: flags
            ),
            instructions: makeInstructions(
                referenceDate: referenceDate,
                route: resolvedRoute,
                flags: flags
            )
        )
    }

    nonisolated private static func legacyToolRoute(query: String) -> CoachQueryRoute {
        if CoachQueryIntent.isScheduleFocused(query) { return .schedule }
        if CoachQueryIntent.isExerciseHistoryFocused(query) { return .exerciseHistory }
        if CoachQueryIntent.isVolumeFocused(query) { return .workoutPrescription }
        return .general
    }
}
