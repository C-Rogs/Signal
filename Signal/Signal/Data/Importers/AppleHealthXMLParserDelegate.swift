import Foundation
import os

final class AppleHealthXMLParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    private let aggregation: DailyMetricAggregationState
    private let nutritionAggregation: DailyNutritionAggregationState
    private var sourceNames = AppleHealthSourceNames()
    private var currentRecord: [String: String] = [:]
    private var currentWorkout: [String: String] = [:]
    private var currentCorrelation: [String: String] = [:]
    private var correlationRecords: [[String: String]] = []
    private var currentWorkoutStatistics: [String: String] = [:]
    private var workoutStatisticsByType: [String: String] = [:]
    private var runningRecordSamples: [RunningRecordSample] = []
    private var poolCounter = 0
    private let poolInterval = 200
    private let progressInterval = 10_000
    private var onParseProgress: (@Sendable (_ recordsScanned: Int, _ tier1RecordsKept: Int) -> Void)?

    private(set) var recordsScanned = 0
    private(set) var tier1RecordsKept = 0
    private(set) var nutritionRecordsKept = 0
    private(set) var workoutsScanned = 0
    private(set) var workoutsKept = 0
    private(set) var skippedUnitCount = 0
    private(set) var skippedDateCount = 0
    private(set) var parsedWorkouts: [AppleWorkout] = []

    var isCancelled: () -> Bool = { false }

    init(
        aggregation: DailyMetricAggregationState,
        nutritionAggregation: DailyNutritionAggregationState,
        onParseProgress: (@Sendable (_ recordsScanned: Int, _ tier1RecordsKept: Int) -> Void)? = nil
    ) {
        self.aggregation = aggregation
        self.nutritionAggregation = nutritionAggregation
        self.onParseProgress = onParseProgress
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "Record":
            currentRecord = attributeDict
        case "Workout":
            currentWorkout = attributeDict
            workoutStatisticsByType = [:]
        case "WorkoutStatistics":
            currentWorkoutStatistics = attributeDict
        case "Correlation":
            currentCorrelation = attributeDict
            correlationRecords = []
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "Record":
            endRecord(parser)
        case "Workout":
            endWorkout(parser)
        case "WorkoutStatistics":
            endWorkoutStatistics()
        case "Correlation":
            endCorrelation()
        default:
            break
        }
    }

    func finishLogging() {
        sourceNames.logDistinctSources()
        Log.import.info(
            "export workouts kept=\(self.workoutsKept, privacy: .public) scanned=\(self.workoutsScanned, privacy: .public) nutritionRecords=\(self.nutritionRecordsKept, privacy: .public)"
        )
    }

    private func endRecord(_ parser: XMLParser) {
        recordsScanned += 1
        poolCounter += 1

        if recordsScanned % progressInterval == 0 {
            onParseProgress?(recordsScanned, tier1RecordsKept)
        }

        if poolCounter >= poolInterval {
            poolCounter = 0
            autoreleasepool {}
            if isCancelled() {
                parser.abortParsing()
                return
            }
        }

        guard let type = currentRecord["type"] else {
            currentRecord = [:]
            return
        }

        if currentCorrelation["type"] == "HKCorrelationTypeIdentifierBloodPressure" {
            correlationRecords.append(currentRecord)
            currentRecord = [:]
            return
        }

        if AppleHealthRecordTypes.runningMechanicTypes.contains(type) {
            ingestRunningMechanicRecord(type: type)
            currentRecord = [:]
            return
        }

        if AppleHealthRecordTypes.nutritionTypes.contains(type) {
            ingestNutritionRecord(type: type)
            currentRecord = [:]
            return
        }

        guard AppleHealthRecordTypes.tier1.contains(type) else {
            currentRecord = [:]
            return
        }

        tier1RecordsKept += 1
        let sourceName = currentRecord["sourceName"]
        sourceNames.record(type: type, sourceName: sourceName)

        switch type {
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            ingestQuantity(type: type, apply: ingestHRV)
        case "HKQuantityTypeIdentifierRestingHeartRate":
            ingestQuantity(type: type, apply: ingestRestingHR)
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            ingestQuantity(type: type, apply: ingestActiveEnergy)
        case "HKQuantityTypeIdentifierBodyMass":
            ingestQuantity(type: type, apply: ingestBodyMass)
        case "HKQuantityTypeIdentifierBodyFatPercentage":
            ingestQuantity(type: type, apply: ingestBodyFat)
        case "HKQuantityTypeIdentifierLeanBodyMass":
            ingestQuantity(type: type, apply: ingestLeanBodyMass)
        case "HKQuantityTypeIdentifierVO2Max":
            ingestQuantity(type: type, apply: ingestVO2Max)
        case "HKQuantityTypeIdentifierRespiratoryRate":
            ingestQuantity(type: type, apply: ingestRespiratoryRate)
        case "HKQuantityTypeIdentifierOxygenSaturation":
            ingestQuantity(type: type, apply: ingestBloodOxygen)
        case "HKQuantityTypeIdentifierAppleSleepingWristTemperature":
            ingestQuantity(type: type, apply: ingestWristTemperature)
        case "HKQuantityTypeIdentifierHeartRate":
            ingestQuantity(type: type, apply: ingestHeartRate)
        case "HKQuantityTypeIdentifierWalkingHeartRateAverage":
            ingestQuantity(type: type, apply: ingestWalkingHeartRate)
        case "HKQuantityTypeIdentifierStepCount":
            ingestQuantity(type: type, apply: ingestStepCount)
        case "HKQuantityTypeIdentifierBasalEnergyBurned":
            ingestQuantity(type: type, apply: ingestBasalEnergy)
        case "HKQuantityTypeIdentifierAppleExerciseTime":
            ingestQuantity(type: type, apply: ingestAppleExerciseTime)
        case "HKQuantityTypeIdentifierPhysicalEffort":
            ingestQuantity(type: type, apply: ingestPhysicalEffort)
        case "HKQuantityTypeIdentifierTimeInDaylight":
            ingestQuantity(type: type, apply: ingestTimeInDaylight)
        case "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances":
            ingestQuantity(type: type, apply: ingestSleepingBreathingDisturbances)
        case "HKCategoryTypeIdentifierSleepAnalysis":
            ingestSleep()
        case "HKCategoryTypeIdentifierAppleStandHour":
            ingestStandHour()
        default:
            break
        }

        currentRecord = [:]
    }

    private func endWorkoutStatistics() {
        guard let type = currentWorkoutStatistics["type"],
              let average = currentWorkoutStatistics["average"]
        else {
            currentWorkoutStatistics = [:]
            return
        }
        workoutStatisticsByType[type] = average
        currentWorkoutStatistics = [:]
    }

    private func endCorrelation() {
        defer {
            currentCorrelation = [:]
            correlationRecords = []
        }
        guard currentCorrelation["type"] == "HKCorrelationTypeIdentifierBloodPressure" else { return }

        var systolic: Double?
        var diastolic: Double?
        var sampleDate: Date?

        for record in correlationRecords {
            guard let recordType = record["type"],
                  let valueString = record["value"],
                  let raw = Double(valueString)
            else {
                continue
            }
            let unit = record["unit"]
            guard let mmHg = AppleHealthUnitNormalizer.normalizedBloodPressureMmHg(value: raw, unit: unit) else {
                skippedUnitCount += 1
                continue
            }
            let dateString = record["startDate"] ?? record["endDate"]
            let parsedDate = dateString.flatMap { AppleHealthDateParser.parse($0) }
            switch recordType {
            case "HKQuantityTypeIdentifierBloodPressureSystolic":
                systolic = mmHg
                if sampleDate == nil { sampleDate = parsedDate }
            case "HKQuantityTypeIdentifierBloodPressureDiastolic":
                diastolic = mmHg
                if sampleDate == nil { sampleDate = parsedDate }
            default:
                break
            }
        }

        guard let systolic, let diastolic, let sampleDate else { return }
        aggregation.addBloodPressure(systolic: systolic, diastolic: diastolic, sampleDate: sampleDate)
    }

    private func endWorkout(_ parser: XMLParser) {
        workoutsScanned += 1
        poolCounter += 1

        if poolCounter >= poolInterval {
            poolCounter = 0
            autoreleasepool {}
            if isCancelled() {
                parser.abortParsing()
                return
            }
        }

        var mechanics = AppleWorkoutMapper.mechanicsFromWorkoutStatistics(workoutStatisticsByType)
        if let startString = currentWorkout["startDate"],
           let endString = currentWorkout["endDate"],
           let start = AppleHealthDateParser.parse(startString),
           let end = AppleHealthDateParser.parse(endString),
           let activityType = currentWorkout["workoutActivityType"],
           AppleWorkoutMapper.isRunningActivity(AppleWorkoutMapper.displayWorkoutTypeNameForExport(activityType))
        {
            AppleWorkoutMapper.applyRecordFallback(
                to: &mechanics,
                workoutStart: start,
                workoutEnd: end,
                samples: runningRecordSamples
            )
        }

        if let workout = AppleWorkoutMapper.fromExportAttributes(currentWorkout, mechanics: mechanics) {
            parsedWorkouts.append(workout)
            workoutsKept += 1
        }
        currentWorkout = [:]
        workoutStatisticsByType = [:]
    }

    private typealias QuantityIngest = (Double, Date) -> Void

    private func ingestQuantity(type: String, apply: QuantityIngest) {
        guard let startString = currentRecord["startDate"],
              let startDate = AppleHealthDateParser.parse(startString)
        else {
            skippedDateCount += 1
            return
        }
        guard let valueString = currentRecord["value"],
              let rawValue = Double(valueString)
        else {
            return
        }

        let unit = currentRecord["unit"]
        let normalized: Double?
        switch type {
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            normalized = AppleHealthUnitNormalizer.normalizedHRV(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierRestingHeartRate":
            normalized = AppleHealthUnitNormalizer.normalizedRestingHR(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            normalized = AppleHealthUnitNormalizer.normalizedActiveEnergyKcal(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierBodyMass":
            normalized = AppleHealthUnitNormalizer.normalizedBodyMassKg(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierBodyFatPercentage":
            normalized = AppleHealthUnitNormalizer.normalizedBodyFatPercentage(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierLeanBodyMass":
            normalized = AppleHealthUnitNormalizer.normalizedLeanBodyMassKg(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierVO2Max":
            normalized = AppleHealthUnitNormalizer.normalizedVO2Max(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierRespiratoryRate":
            normalized = AppleHealthUnitNormalizer.normalizedRespiratoryRate(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierOxygenSaturation":
            normalized = AppleHealthUnitNormalizer.normalizedBloodOxygenPct(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierAppleSleepingWristTemperature":
            normalized = AppleHealthUnitNormalizer.normalizedWristTemperatureDeltaC(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierHeartRate":
            normalized = AppleHealthUnitNormalizer.normalizedHeartRate(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierWalkingHeartRateAverage":
            normalized = AppleHealthUnitNormalizer.normalizedHeartRate(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierStepCount":
            normalized = AppleHealthUnitNormalizer.normalizedStepCount(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierBasalEnergyBurned":
            normalized = AppleHealthUnitNormalizer.normalizedBasalEnergyKcal(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierAppleExerciseTime":
            normalized = AppleHealthUnitNormalizer.normalizedMinutes(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierPhysicalEffort":
            normalized = AppleHealthUnitNormalizer.normalizedPhysicalEffort(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierTimeInDaylight":
            normalized = AppleHealthUnitNormalizer.normalizedMinutes(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances":
            normalized = rawValue.isFinite ? rawValue : nil
        default:
            normalized = nil
        }

        guard let value = normalized else {
            skippedUnitCount += 1
            return
        }
        apply(value, startDate)
    }

    private func ingestNutritionRecord(type: String) {
        guard let startString = currentRecord["startDate"],
              let startDate = AppleHealthDateParser.parse(startString),
              let valueString = currentRecord["value"],
              let rawValue = Double(valueString)
        else {
            skippedDateCount += 1
            return
        }

        let unit = currentRecord["unit"]
        let normalized: Double?
        switch type {
        case "HKQuantityTypeIdentifierDietaryEnergyConsumed":
            normalized = AppleHealthUnitNormalizer.normalizedActiveEnergyKcal(value: rawValue, unit: unit)
        case "HKQuantityTypeIdentifierDietarySodium":
            normalized = AppleHealthUnitNormalizer.normalizedMilligrams(value: rawValue, unit: unit)
        default:
            normalized = AppleHealthUnitNormalizer.normalizedGrams(value: rawValue, unit: unit)
        }

        guard let value = normalized else {
            skippedUnitCount += 1
            return
        }

        nutritionRecordsKept += 1
        switch type {
        case "HKQuantityTypeIdentifierDietaryEnergyConsumed":
            nutritionAggregation.addDietaryEnergy(kcal: value, startDate: startDate)
        case "HKQuantityTypeIdentifierDietaryProtein":
            nutritionAggregation.addProtein(g: value, startDate: startDate)
        case "HKQuantityTypeIdentifierDietaryCarbohydrates":
            nutritionAggregation.addCarbs(g: value, startDate: startDate)
        case "HKQuantityTypeIdentifierDietaryFatTotal":
            nutritionAggregation.addFatTotal(g: value, startDate: startDate)
        case "HKQuantityTypeIdentifierDietaryFatSaturated":
            nutritionAggregation.addFatSaturated(g: value, startDate: startDate)
        case "HKQuantityTypeIdentifierDietaryFiber":
            nutritionAggregation.addFiber(g: value, startDate: startDate)
        case "HKQuantityTypeIdentifierDietarySugar":
            nutritionAggregation.addSugar(g: value, startDate: startDate)
        case "HKQuantityTypeIdentifierDietarySodium":
            nutritionAggregation.addSodium(mg: value, startDate: startDate)
        default:
            break
        }
    }

    private func ingestRunningMechanicRecord(type: String) {
        guard let startString = currentRecord["startDate"],
              let startDate = AppleHealthDateParser.parse(startString),
              let valueString = currentRecord["value"],
              let rawValue = Double(valueString)
        else {
            return
        }
        let unit = currentRecord["unit"]
        let normalized: Double?
        switch type {
        case "HKQuantityTypeIdentifierRunningPower":
            normalized = rawValue.isFinite ? rawValue : nil
        case "HKQuantityTypeIdentifierRunningStrideLength":
            normalized = rawValue.isFinite ? rawValue : nil
        case "HKQuantityTypeIdentifierRunningVerticalOscillation":
            normalized = rawValue.isFinite ? rawValue : nil
        case "HKQuantityTypeIdentifierRunningGroundContactTime":
            normalized = rawValue.isFinite ? rawValue : nil
        case "HKQuantityTypeIdentifierRunningSpeed":
            normalized = AppleHealthUnitNormalizer.normalizedRunningSpeedKmh(value: rawValue, unit: unit)
        default:
            normalized = nil
        }
        guard let value = normalized else { return }
        runningRecordSamples.append(RunningRecordSample(type: type, value: value, date: startDate))
    }

    private func ingestHRV(value: Double, startDate: Date) {
        aggregation.addHRV(value: value, startDate: startDate)
    }

    private func ingestRestingHR(value: Double, startDate: Date) {
        aggregation.addRestingHR(value: value, startDate: startDate)
    }

    private func ingestActiveEnergy(value: Double, startDate: Date) {
        aggregation.addActiveEnergy(kcal: value, startDate: startDate)
    }

    private func ingestBodyMass(value: Double, startDate: Date) {
        let endString = currentRecord["endDate"]
        let sampleDate = endString.flatMap { AppleHealthDateParser.parse($0) } ?? startDate
        aggregation.addBodyMass(kg: value, sampleDate: sampleDate)
    }

    private func ingestBodyFat(value: Double, startDate: Date) {
        let endString = currentRecord["endDate"]
        let sampleDate = endString.flatMap { AppleHealthDateParser.parse($0) } ?? startDate
        aggregation.addBodyFatPercentage(pct: value, sampleDate: sampleDate)
    }

    private func ingestLeanBodyMass(value: Double, startDate: Date) {
        let endString = currentRecord["endDate"]
        let sampleDate = endString.flatMap { AppleHealthDateParser.parse($0) } ?? startDate
        aggregation.addLeanBodyMass(kg: value, sampleDate: sampleDate)
    }

    private func ingestVO2Max(value: Double, startDate: Date) {
        let endString = currentRecord["endDate"]
        let sampleDate = endString.flatMap { AppleHealthDateParser.parse($0) } ?? startDate
        aggregation.addVO2Max(value: value, sampleDate: sampleDate)
    }

    private func ingestRespiratoryRate(value: Double, startDate: Date) {
        aggregation.addRespiratoryRate(brpm: value, sampleDate: startDate)
    }

    private func ingestBloodOxygen(value: Double, startDate: Date) {
        aggregation.addBloodOxygenPct(pct: value, sampleDate: startDate)
    }

    private func ingestWristTemperature(value: Double, startDate: Date) {
        aggregation.addWristTemperatureDeltaC(delta: value, sampleDate: startDate)
    }

    private func ingestHeartRate(value: Double, startDate: Date) {
        aggregation.addHeartRate(bpm: value, sampleDate: startDate)
    }

    private func ingestWalkingHeartRate(value: Double, startDate: Date) {
        aggregation.addWalkingHeartRate(bpm: value, startDate: startDate)
    }

    private func ingestStepCount(value: Double, startDate: Date) {
        aggregation.addStepCount(count: value, startDate: startDate)
    }

    private func ingestBasalEnergy(value: Double, startDate: Date) {
        aggregation.addBasalEnergy(kcal: value, startDate: startDate)
    }

    private func ingestAppleExerciseTime(value: Double, startDate: Date) {
        aggregation.addAppleExerciseTime(minutes: value, startDate: startDate)
    }

    private func ingestPhysicalEffort(value: Double, startDate: Date) {
        aggregation.addPhysicalEffort(value: value, startDate: startDate)
    }

    private func ingestTimeInDaylight(value: Double, startDate: Date) {
        aggregation.addTimeInDaylight(minutes: value, startDate: startDate)
    }

    private func ingestSleepingBreathingDisturbances(value: Double, startDate: Date) {
        aggregation.addSleepingBreathingDisturbances(count: value, sampleDate: startDate)
    }

    private func ingestSleep() {
        guard let value = currentRecord["value"],
              AppleHealthRecordTypes.isAsleepCategoryValue(value)
        else {
            return
        }
        guard let startString = currentRecord["startDate"],
              let endString = currentRecord["endDate"],
              let start = AppleHealthDateParser.parse(startString),
              let end = AppleHealthDateParser.parse(endString)
        else {
            skippedDateCount += 1
            return
        }

        let isLegacy = AppleHealthRecordTypes.isLegacyAsleep(value)
        aggregation.addSleepInterval(start: start, end: end, isLegacy: isLegacy)
    }

    private func ingestStandHour() {
        guard currentRecord["value"] == AppleHealthRecordTypes.appleStandHourStood,
              let startString = currentRecord["startDate"],
              let start = AppleHealthDateParser.parse(startString)
        else {
            return
        }
        aggregation.addAppleStandHour(stood: true, startDate: start)
    }
}

private extension AppleWorkoutMapper {
    static func displayWorkoutTypeNameForExport(_ exportType: String) -> String {
        if exportType.hasPrefix("HKWorkoutActivityType") {
            let suffix = exportType.dropFirst("HKWorkoutActivityType".count)
            return String(suffix)
        }
        return exportType
    }
}

enum AppleHealthXMLParseError: LocalizedError, Sendable {
    case cannotOpenStream
    case parseFailed(underlying: Error?)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotOpenStream:
            "Could not open export.xml for reading. Download the file in Files or pick a local copy, then try again."
        case .parseFailed(let underlying):
            if let underlying {
                "Apple Health XML parse failed: \(underlying.localizedDescription)"
            } else {
                "Apple Health XML parse failed."
            }
        case .cancelled:
            "Apple Health import cancelled."
        }
    }
}

enum AppleHealthXMLParser {
    nonisolated static func parse(
        fileURL: URL,
        aggregation: DailyMetricAggregationState,
        nutritionAggregation: DailyNutritionAggregationState,
        isCancelled: @escaping () -> Bool,
        onParseProgress: (@Sendable (_ recordsScanned: Int, _ tier1RecordsKept: Int) -> Void)? = nil
    ) throws -> AppleHealthXMLParserDelegate {
        let hasScope = fileURL.startAccessingSecurityScopedResource()
        if !hasScope {
            Log.import.warning("security-scoped access not granted; attempting parse anyway")
        }
        defer {
            if hasScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let stream = InputStream(url: fileURL) else {
            throw AppleHealthXMLParseError.cannotOpenStream
        }
        stream.open()
        defer { stream.close() }

        let delegate = AppleHealthXMLParserDelegate(
            aggregation: aggregation,
            nutritionAggregation: nutritionAggregation,
            onParseProgress: onParseProgress
        )
        delegate.isCancelled = isCancelled

        let parser = XMLParser(stream: stream)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        let started = Date()
        let success = parser.parse()
        delegate.finishLogging()

        let elapsed = Date().timeIntervalSince(started)
        Log.import.info(
            "parse finished success=\(success, privacy: .public) scanned=\(delegate.recordsScanned, privacy: .public) tier1=\(delegate.tier1RecordsKept, privacy: .public) days=\(aggregation.dayCount, privacy: .public) nutritionDays=\(nutritionAggregation.allDayStarts().count, privacy: .public) elapsedSec=\(elapsed, format: .fixed(precision: 2), privacy: .public)"
        )

        if isCancelled() {
            throw AppleHealthXMLParseError.cancelled
        }
        if !success {
            throw AppleHealthXMLParseError.parseFailed(underlying: parser.parserError)
        }
        return delegate
    }
}
