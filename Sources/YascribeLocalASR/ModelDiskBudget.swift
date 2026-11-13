import Foundation

/// Wolne bajty dotyczą całego woluminu; kilka katalogów na tym samym woluminie dzieli jeden budżet.
public struct ModelDiskLocation: Equatable, Sendable {
    public let volume: String
    public let freeBytes: Int64
    public let path: String
    public init(volume: String, freeBytes: Int64, path: String = "/test") {
        self.volume = volume; self.freeBytes = freeBytes; self.path = path
    }
}

public struct ModelDiskNeed: Equatable, Sendable {
    public let volume: String
    public let bytes: Int64
    public let freeBytes: Int64
    public let path: String
    public var message: String {
        String(format: "Not enough disk space at %@: need %.2f GB, available %.2f GB.",
               path, Double(bytes) / 1e9, Double(freeBytes) / 1e9)
    }
    public var fits: Bool { freeBytes >= bytes }
}

public enum ModelDiskBudget {
    public enum Operation: Sendable { case download, load }

    /// Spike TASK-102 README §5, §8, §9: kompilacja ≈ 2× modelu (TMP + staging w magazynie),
    /// E5RT ≈ 2,3× także przy gotowym compiled/. Zapas 1 GB na lokalizację przechowującą model.
    /// Pobieranie rezerwuje też TMP na plik pobrania, zanim trafi do .part w magazynie.
    public static func need(modelBytes: Int64, operation: Operation,
                            missingBytes: Int64? = nil, largestMissingFile: Int64? = nil, compiledReady: Bool = false,
                            store: ModelDiskLocation, temporary: ModelDiskLocation, e5rt: ModelDiskLocation) -> [ModelDiskNeed] {
        let reserve: Int64 = 1_000_000_000
        let compiling = operation == .load && !compiledReady
        let allocations: [(ModelDiskLocation, Int64)] = [
            (store, (operation == .download ? missingBytes ?? modelBytes : (compiling ? modelBytes : 0)) + reserve),
            (temporary, operation == .download ? (temporary.volume != store.volume ? largestMissingFile ?? modelBytes : 0) : (compiling ? modelBytes : 0)),
            (e5rt, operation == .load ? (modelBytes * 23 + 9) / 10 : 0),
        ]
        var totals: [String: (need: Int64, free: Int64, path: String)] = [:]
        for (location, bytes) in allocations where bytes > 0 {
            let previous = totals[location.volume] ?? (0, location.freeBytes, location.path)
            totals[location.volume] = (previous.need + bytes, min(previous.free, location.freeBytes), previous.path)
        }
        return totals.sorted { $0.key < $1.key }.map { ModelDiskNeed(volume: $0.key, bytes: $0.value.need, freeBytes: $0.value.free, path: $0.value.path) }
    }

    public static func inspect(_ url: URL) throws -> ModelDiskLocation {
        var existing = url
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            existing.deleteLastPathComponent()
        }
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: existing.path)
        let values = try existing.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values.volumeAvailableCapacityForImportantUsage,
              let volume = attrs[.systemNumber] as? NSNumber else {
            throw ModelStoreError(message: "Cannot determine available disk space at \(existing.path).")
        }
        return ModelDiskLocation(volume: volume.stringValue, freeBytes: free, path: url.path)
    }
}
