import Foundation
import os

final class AppleHealthXMLParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    private let aggregation: DailyMetricAggregationState
    private var sourceNames = AppleHealthSourceNames()
    private var currentRecord: [String: String] = [:]
    private var poolCounter = 0
    private let poolInterval = 200

    private(set) var recordsScanned = 0
    private(set) var tier1RecordsKept = 0
    private(set) var skippedUnitCount = 0
    private(set) var skippedDateCount = 0

    var isCancelled: () -> Bool = { false }

    init(aggregation: DailyMetricAggregationState) {
        self.aggregation = aggregation
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "Record" else { return }
        currentRecord = attributeDict
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "Record" else { return }
        recordsScanned += 1
        poolCounter += 1

        if poolCounter >= poolInterval {
            poolCounter = 0
            autoreleasepool {}
            if isCancelled() {
                parser.abortParsing()
                return
            }
        }

        guard let type = currentRecord["type"], AppleHealthRecordTypes.tier1.contains(type) else {
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
        case "HKCategoryTypeIdentifierSleepAnalysis":
            ingestSleep()
        default:
            break
        }

        currentRecord = [:]
    }

    func finishLogging() {
        sourceNames.logDistinctSources()
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
        default:
            normalized = nil
        }

        guard let value = normalized else {
            skippedUnitCount += 1
            return
        }
        apply(value, startDate)
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
        isCancelled: @escaping () -> Bool
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

        let delegate = AppleHealthXMLParserDelegate(aggregation: aggregation)
        delegate.isCancelled = isCancelled

        let parser = XMLParser(stream: stream)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        let started = Date()
        let success = parser.parse()
        delegate.finishLogging()

        let elapsed = Date().timeIntervalSince(started)
        Log.import.info(
            "parse finished success=\(success, privacy: .public) scanned=\(delegate.recordsScanned, privacy: .public) tier1=\(delegate.tier1RecordsKept, privacy: .public) days=\(aggregation.dayCount, privacy: .public) elapsedSec=\(elapsed, format: .fixed(precision: 2), privacy: .public)"
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
