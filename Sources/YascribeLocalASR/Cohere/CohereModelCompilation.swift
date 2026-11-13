// Źródło: altic-dev/FluidAudio@386f7195670b77f2954c7ee143ec63fcb50b6c3b, Sources/FluidAudio/ASR/Cohere/CohereTranscribeAsrModels.swift
// Licencja: Apache-2.0 (LICENSES/Apache-2.0.txt).
// Zmodyfikowano w Yascribe: klucz z odcisku, inwentarz komponentu, staging i atomowa publikacja, bez blokady oczekującej.

import CoreML
import CryptoKit
import Darwin
import Foundation

/// Wywołujący utrzymuje ModelStore.acquireLock() przez sprawdzenie źródeł, kompilację i cały czas życia modeli.
/// Ten pomocnik nie tworzy blokad: nie może czekać ani zastępować tokenu właściciela.
enum CohereModelCompilation {
    static let formatVersion = 1
    static let packages = ["cohere_frontend.mlpackage", "cohere_encoder.mlpackage",
                           "cohere_decoder_fullseq_masked.mlpackage", "cohere_decoder_cached.mlpackage"]
    private static let inventoryName = ".yascribe-files.json"

    static func key(fingerprint: String, configuration: CohereTranscribeComputeConfiguration,
                    version: Int = formatVersion) -> String {
        let units = [configuration.frontend, configuration.encoder, configuration.crossKV, configuration.decoder]
            .map { String($0.rawValue) }.joined(separator: ",")
        return SHA256.hash(data: Data("\(version)\n\(fingerprint)\n\(units)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func directory(package: String, root: URL, key: String) -> URL {
        root.appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: package).deletingPathExtension().lastPathComponent + ".mlmodelc", isDirectory: true)
    }

    static func isComplete(at directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(inventoryName)),
              let files = try? JSONDecoder().decode([String: Int64].self, from: data),
              files["coremldata.bin"] != nil, files["model.mil"] != nil else { return false }
        return files.allSatisfy { name, size in
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), size > 0,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path),
                  attrs[.type] as? FileAttributeType == .typeRegular else { return false }
            return (attrs[.size] as? NSNumber)?.int64Value == size
        }
    }

    static func compile(package: URL, root: URL, key: String,
                        copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
                        compiler: (URL) throws -> URL = { try MLModel.compileModel(at: $0) }) throws -> URL {
        let fm = FileManager.default
        let destination = directory(package: package.lastPathComponent, root: root, key: key)
        if isComplete(at: destination) { return destination }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = try compiler(package)
        let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: temporary)
            try? fm.removeItem(at: staging)
        }
        try copy(temporary, staging)
        var files: [String: Int64] = [:]
        // Enumerator ścieżkowy zwraca nazwy względne bez różnic między /var a /private/var.
        guard let items = fm.enumerator(atPath: staging.path) else {
            throw ModelStoreError(message: "Cannot inspect compiled model.")
        }
        for case let name as String in items {
            let attributes = try fm.attributesOfItem(atPath: staging.appendingPathComponent(name).path)
            if attributes[.type] as? FileAttributeType == .typeRegular {
                files[name] = (attributes[.size] as? NSNumber)?.int64Value
            }
        }
        try JSONEncoder().encode(files).write(to: staging.appendingPathComponent(inventoryName))
        guard isComplete(at: staging) else { throw ModelStoreError(message: "The compiled model is incomplete.") }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        guard rename(staging.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return destination
    }
}
