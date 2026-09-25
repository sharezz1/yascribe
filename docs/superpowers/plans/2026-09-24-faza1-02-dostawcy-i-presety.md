# Plan B — dostawcy, sonda i presety

> **Dla wykonawcy (Hermes):** najpierw przegląd §0 „Instrukcja dla Hermesa". Jedno zadanie = jedna sesja. Kroki używają pól `- [ ]`.

**Cel:** klient API zgodnego z OpenAI (OpenRouter, Ollama, oMLX, LM Studio), sonda możliwości modelu per rola z klasyfikacją obsługi języka, presety z językiem obowiązkowym i ich zapis — oraz `meetnotes-cli models` i `probe`.

**Architektura:** `MeetNotesProviders` jest liściem grafu: nie zależy od nagrywania ani transkrypcji. Dialekt jest jeden (OpenAI-zgodny), możliwości modeli rozstrzyga sonda żądaniem próbnym, a nie wiedza wpisana w kod. Klucze w pęku kluczy, nigdy w pliku. Nagrania próbne jako base64 w pliku źródłowym generowanym skryptem.

**Stos:** Swift 6.4, Foundation (URLSession, JSONSerialization), Security (`SecItem*`), `say` + `afconvert` do generowania nagrań próbnych.

**Specyfikacja:** `docs/superpowers/specs/2026-09-24-faza1-warstwa-dostawcow-design.md` §3–§5, §7, §10 (po poprawkach z zadania 0). Przegląd: `docs/superpowers/plans/2026-09-24-faza1-00-przeglad.md`.

## Wspólne ograniczenia

Obowiązują w całości: przegląd §4. Najważniejsze dla tego planu:

- Transkrypcja: `POST {base}/audio/transcriptions`, ciało JSON `{"model", "input_audio": {"data": <base64 WAV>, "format": "wav"}, "language", "response_format": "verbose_json", "timestamp_granularities": ["word"]}` — kształt z wywołania z rozdz. 11 dla OpenRoutera.
- Kształt czatowy: `POST {base}/chat/completions` z treścią `[{"type":"text",...},{"type":"input_audio","input_audio":{...}}]`; brak znaczników słów.
- 🔴 `LanguageCode` nie powstaje z `"auto"`, pustego napisu ani kodu innego niż dwie litery.
- 🔴 Preset bez języka albo bez ASR nie przechodzi `validate()`; `PresetsFile.upsert` waliduje (P7).
- 🔴 Embedding nie jest polem presetu — mieszka w `GlobalSettings` (P13).
- Klucz: `KeychainSecretStore(service: "meetnotes.provider")`, konto = UUID dostawcy. W interfejsie tylko `maskedKey` (ostatnie 4 znaki).
- Testy automatyczne **nie dotykają pęku kluczy** użytkownika — `InMemorySecretStore`. Pęk kluczy sprawdza ręcznie B5.

## Na co patrzeć przy przeglądzie

1. **Model transkrypcyjny wpisany z ręki, którego nie ma w liście modeli** → sonda go przyjmuje. Test `transcriptionModelTypedByHandPassesTheProbe` (B2).
2. **API odrzuca parametr `language` błędem 400** → klasa „automatyczny", nie „wymuszony". Test `rejectedLanguageParameterMeansAutomatic` (B2).
3. **Model niedeterministyczny** (dwa przebiegi bez języka różne) → „nie wiadomo", nigdy fałszywe „wymuszony". Test `nondeterministicModelIsNotClassified` (B2).
4. **Odpowiedź 401 z ciałem błędu** → błąd niesie status, ale nigdy klucza. Test `httpErrorCarriesStatusButNeverTheKey` (B1).
5. **`"AUTO"` w pliku presetów na dysku** → dekodowanie pada, zamiast po cichu przyjąć. Test `autoLanguageCannotBeConstructed` (B3).

---

### Zadanie B1: Klient dostawcy

Status: ✅ zweryfikowane (4 testy). Piąty test ze spike'a, `providerFileNeverContainsAKey`, jest w B3 — używa `ProvidersFile` z B3 (Hermes 2.2).

**Pliki:**
- Utwórz: `scripts/make-probe-clips.sh`
- Utwórz: `Sources/MeetNotesProviders/LanguageCode.swift`, `ProbeClips.swift`, `ProbeClips+Data.swift` (generowany), `Provider.swift`, `SecretStore.swift`, `HTTPClient.swift`, `OpenAICompatibleClient.swift`
- Usuń: `Sources/MeetNotesProviders/_Placeholder.swift`, `Tests/MeetNotesProvidersTests/_Placeholder.swift`
- Test: `Tests/MeetNotesProvidersTests/Stub.swift`, `Tests/MeetNotesProvidersTests/ClientTests.swift`

**Interfejsy:**
- Dostarcza: `LanguageCode(_:) throws` (`rawValue`, `.polish`, `.english`, `selectable: [(code, name)]`), `LanguageCodeError.empty`, `.autoIsForbidden`, `.malformed(String)`. `ProbeClip` (`language`, `wav`, `expectedWords`), `ProbeClips.polish`, `.english`, `clip(for:)`, `mismatched(for:)`, `matches(_:_:)`, `normalize(_:)`. `Provider(id:name:baseURL:)`, `ProviderError.http(Int, String)`, `.badResponse(String)`, `.missingKey`. `SecretStore` (`get`, `set`, `delete` po UUID), `KeychainSecretStore(service:)`, `InMemorySecretStore()`, `maskedKey(_:)`. `HTTPClient` (`send(_:) async throws -> (Data, HTTPURLResponse)`), `URLSessionHTTPClient()`. `ASRShape` (`.audioTranscriptions`, `.chatAudio`), `ModelInfo` (`id`, `inputModalities`, `outputModalities`), `TranscribedWord(word:start:end:)`, `TranscriptionResult(text:words:)`. `OpenAICompatibleClient(provider:key:http:)`: `listModels()`, `transcribe(wav:model:language:shape:)`, `chat(model:system:user:)`, `embed(model:text:)`.

- [ ] **Krok 1: Nagrania próbne.** Utwórz `scripts/make-probe-clips.sh` (`chmod +x`):

```bash
#!/bin/bash
# Generuje nagrania próbne sondy ASR (spec fazy 1, §1.5): „raz, dwa, trzy" po
# polsku (rozdz. 4 daje tę frazę) i „one, two, three" po angielsku, 16 kHz mono,
# i zapisuje je jako base64 w pliku źródłowym. Zasoby SwiftPM odpadają: przy
# ręcznie składanym .app lądują w korzeniu paczki i psują podpis.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"
say -v Zosia -o "$T/pl.aiff" "raz, dwa, trzy"
say -v Samantha -o "$T/en.aiff" "one, two, three"
afconvert -f WAVE -d LEI16@16000 -c 1 "$T/pl.aiff" "$T/pl.wav"
afconvert -f WAVE -d LEI16@16000 -c 1 "$T/en.aiff" "$T/en.wav"
OUT=Sources/MeetNotesProviders/ProbeClips+Data.swift
{
  echo "// WYGENEROWANE przez scripts/make-probe-clips.sh — nie edytuj ręcznie."
  echo "extension ProbeClips {"
  echo "    static let polishBase64 = \"$(base64 -i "$T/pl.wav" | tr -d '\n')\""
  echo "    static let englishBase64 = \"$(base64 -i "$T/en.wav" | tr -d '\n')\""
  echo "}"
} > "$OUT"
rm -rf "$T"
echo "zapisano $OUT"
```

Uruchom `scripts/make-probe-clips.sh` — oczekiwane: `zapisano Sources/MeetNotesProviders/ProbeClips+Data.swift`, plik ~170 KB. Wymaga głosów `Zosia` (pl_PL) i `Samantha` (en_US): `say -v '?' | grep -E 'Zosia|Samantha'`. Plik jest generowany, więc jego zawartość nie jest w planie. Testy porównują nagranie z samym sobą, więc każda wygenerowana wersja jest poprawna.

- [ ] **Krok 2: Testy, które padną.** Usuń obie zaślepki dostawców i utwórz:

`Tests/MeetNotesProvidersTests/Stub.swift`:

```swift
import Foundation
@testable import MeetNotesProviders

/// Klient HTTP z odpowiedziami z ręki. Zapisuje żądania, żeby testy mogły
/// sprawdzić, co poszło w sieć.
final class StubHTTP: HTTPClient, @unchecked Sendable {
    struct Call { let path: String; let body: [String: Any]; let headers: [String: String] }
    private let lock = NSLock()
    private(set) var calls: [Call] = []
    let respond: @Sendable (String, [String: Any]) -> (Int, Any)

    init(_ respond: @escaping @Sendable (String, [String: Any]) -> (Int, Any)) { self.respond = respond }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        lock.withLock { calls.append(Call(path: path, body: body, headers: request.allHTTPHeaderFields ?? [:])) }
        let (status, obj) = respond(path, body)
        let data = try (obj as? String).map { Data($0.utf8) } ?? JSONSerialization.data(withJSONObject: obj)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

let openRouter = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)

/// Czy wysłane nagranie to polskie „raz, dwa, trzy".
func isPolishClip(_ body: [String: Any]) -> Bool {
    let audio = (body["input_audio"] as? [String: Any]) ?? (((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])?
        .first { $0["type"] as? String == "input_audio" }?["input_audio"] as? [String: Any])
    return (audio?["data"] as? String) == ProbeClips.polish.wav.base64EncodedString()
}

/// Odpowiedzi stuba. Jawne typy: przy wyrażeniu warunkowym mieszającym słownik
/// i napis kompilator Swift 6.4 gubi się we wnioskowaniu typów.
func ok(_ obj: [String: Any]) -> (Int, Any) { (200, obj) }
func fail(_ status: Int, _ text: String = "{}") -> (Int, Any) { (status, text) }
func transcript(_ text: String) -> (Int, Any) { ok(["text": text]) }
func chatReply(_ text: String) -> (Int, Any) { ok(["choices": [["message": ["content": text]]]]) }
```

`Tests/MeetNotesProvidersTests/ClientTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesProviders

@Test func listsModelsWithModalities() async throws {
    let http = StubHTTP { _, _ in ok(["data": [
        ["id": "google/gemini-3.8-flash", "architecture": ["input_modalities": ["text", "audio"], "output_modalities": ["text"]]],
        ["id": "deepseek/deepseek-v4.1-flash"],
    ]]) }
    let models = try await OpenAICompatibleClient(provider: openRouter, key: "sk-or-secret", http: http).listModels()
    #expect(models.map(\.id) == ["google/gemini-3.8-flash", "deepseek/deepseek-v4.1-flash"])
    #expect(models[0].inputModalities == ["text", "audio"])
    #expect(http.calls[0].path == "/api/v1/models")
    #expect(http.calls[0].headers["Authorization"] == "Bearer sk-or-secret")
}

@Test func transcriptionSendsLanguageAndAsksForWordTimestamps() async throws {
    let http = StubHTTP { _, _ in ok(["text": "raz dwa trzy", "words": [
        ["word": "raz", "start": 0.1, "end": 0.4], ["word": "dwa", "start": 0.6, "end": 0.9],
    ]]) }
    let c = OpenAICompatibleClient(provider: openRouter, key: "k", http: http)
    let r = try await c.transcribe(wav: ProbeClips.polish.wav, model: "microsoft/mai-transcribe-2", language: .polish,
                                   shape: .audioTranscriptions)
    let body = http.calls[0].body
    #expect(http.calls[0].path == "/api/v1/audio/transcriptions")
    #expect(body["language"] as? String == "pl")
    #expect(body["timestamp_granularities"] as? [String] == ["word"])
    #expect((body["input_audio"] as? [String: Any])?["format"] as? String == "wav")
    #expect(r.words?.count == 2)
    #expect(r.words?[1] == TranscribedWord(word: "dwa", start: 0.6, end: 0.9))
}

@Test func chatShapeReturnsTextWithoutTimestamps() async throws {
    let http = StubHTTP { _, _ in chatReply("raz, dwa, trzy") }
    let r = try await OpenAICompatibleClient(provider: openRouter, key: "k", http: http)
        .transcribe(wav: ProbeClips.polish.wav, model: "google/gemini-3.8-flash", language: .polish, shape: .chatAudio)
    #expect(r.text == "raz, dwa, trzy")
    #expect(r.words == nil)
    #expect(http.calls[0].path == "/api/v1/chat/completions")
}

@Test func httpErrorCarriesStatusButNeverTheKey() async throws {
    // P8: klucz nie może wyciec przez komunikat błędu.
    let http = StubHTTP { _, _ in fail(401, "{\"error\":\"invalid api key\"}") }
    let c = OpenAICompatibleClient(provider: openRouter, key: "sk-or-v1-SECRET123", http: http)
    do {
        _ = try await c.listModels()
        Issue.record("oczekiwano błędu")
    } catch {
        #expect(error as? ProviderError == .http(401, "{\"error\":\"invalid api key\"}"))
        #expect(!"\(error)".contains("SECRET123"))
    }
}
```

- [ ] **Krok 3: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesProvidersTests` — oczekiwane: kod `1`, `cannot find … in scope` m.in. dla `HTTPClient`, `Provider`, `ProbeClips`, `OpenAICompatibleClient`.

- [ ] **Krok 4: Implementacja.**

`Sources/MeetNotesProviders/LanguageCode.swift`:

```swift
import Foundation

public enum LanguageCodeError: Error, Equatable {
    case empty
    /// 🔴 Nigdy `auto` (W§2, rozdz. 14: 62% zmyślonej angielszczyzny).
    case autoIsForbidden
    case malformed(String)
}

/// Kod języka ISO 639-1. Nie da się go zbudować z `auto` ani z pustego napisu —
/// „nigdy auto" jest egzekwowane typem, nie komentarzem.
public struct LanguageCode: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ raw: String) throws {
        let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !v.isEmpty else { throw LanguageCodeError.empty }
        guard v != "auto" else { throw LanguageCodeError.autoIsForbidden }
        guard v.count == 2, v.allSatisfy({ $0.isASCII && $0.isLetter }) else { throw LanguageCodeError.malformed(raw) }
        rawValue = v
    }

    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let polish = try! LanguageCode("pl")
    public static let english = try! LanguageCode("en")

    /// Języki do wyboru w presecie, z nazwami po angielsku (interfejs jest po angielsku).
    public static let selectable: [(code: LanguageCode, name: String)] = [
        ("pl", "Polish"), ("en", "English"), ("de", "German"), ("fr", "French"), ("es", "Spanish"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("cs", "Czech"), ("sk", "Slovak"),
        ("uk", "Ukrainian"), ("ru", "Russian"), ("sv", "Swedish"), ("da", "Danish"), ("fi", "Finnish"),
    ].map { (try! LanguageCode($0.0), $0.1) }
}
```

`Sources/MeetNotesProviders/ProbeClips.swift`:

```swift
import Foundation

/// Nagranie próbne o znanej treści. Dane: `ProbeClips+Data.swift` (wygenerowane).
public struct ProbeClip: Sendable {
    public let language: LanguageCode
    public let wav: Data
    public let expectedWords: [String]
}

public enum ProbeClips {
    public static let polish = ProbeClip(language: .polish, wav: Data(base64Encoded: polishBase64)!,
                                         expectedWords: ["raz", "dwa", "trzy"])
    public static let english = ProbeClip(language: .english, wav: Data(base64Encoded: englishBase64)!,
                                          expectedWords: ["one", "two", "three"])

    public static func clip(for language: LanguageCode) -> ProbeClip? {
        switch language {
        case .polish: polish
        case .english: english
        default: nil
        }
    }

    /// Nagranie w **innym** języku niż preset — do sondy honorowania języka.
    public static func mismatched(for language: LanguageCode) -> ProbeClip {
        language == .english ? polish : english
    }

    /// Czy transkrypt zawiera co najmniej 2 z 3 oczekiwanych słów.
    public static func matches(_ text: String, _ clip: ProbeClip) -> Bool {
        let words = Set(normalize(text).split(separator: " ").map(String.init))
        return clip.expectedWords.filter { words.contains($0) }.count >= 2
    }

    public static func normalize(_ s: String) -> String {
        s.lowercased()
            .unicodeScalars.map { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }
}
```

`Sources/MeetNotesProviders/Provider.swift`:

```swift
import Foundation

/// Dostawca to **instancja**, nie typ: dwa OpenRoutery z różnymi kluczami to dwaj
/// dostawcy (spec fazy 1, §3). Klucz nie jest polem tej struktury — mieszka
/// w pęku kluczy, pod `id`.
public struct Provider: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Np. `https://openrouter.ai/api/v1`, `http://localhost:11434/v1`.
    public var baseURL: URL

    public init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}

public enum ProviderError: Error, Equatable {
    case http(Int, String)
    case badResponse(String)
    case missingKey
}
```

`Sources/MeetNotesProviders/SecretStore.swift`:

```swift
import Foundation
import Security

/// Klucze API: w pęku kluczy, nigdy w pliku ustawień ani w logu (spec fazy 1, §7, P8).
public protocol SecretStore: Sendable {
    func get(_ id: UUID) throws -> String?
    func set(_ id: UUID, _ value: String) throws
    func delete(_ id: UUID) throws
}

public enum SecretStoreError: Error, Equatable {
    case keychain(Int32)
}

public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "meetnotes.provider") { self.service = service }

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func get(_ id: UUID) throws -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { return nil }
        guard st == errSecSuccess, let d = out as? Data else { throw SecretStoreError.keychain(st) }
        return String(decoding: d, as: UTF8.self)
    }

    public func set(_ id: UUID, _ value: String) throws {
        let data = Data(value.utf8)
        let st = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecItemNotFound {
            var q = query(id)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let st2 = SecItemAdd(q as CFDictionary, nil)
            guard st2 == errSecSuccess else { throw SecretStoreError.keychain(st2) }
        } else if st != errSecSuccess {
            throw SecretStoreError.keychain(st)
        }
    }

    public func delete(_ id: UUID) throws {
        let st = SecItemDelete(query(id) as CFDictionary)
        guard st == errSecSuccess || st == errSecItemNotFound else { throw SecretStoreError.keychain(st) }
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    public init() {}
    public func get(_ id: UUID) throws -> String? { lock.lock(); defer { lock.unlock() }; return values[id] }
    public func set(_ id: UUID, _ value: String) throws { lock.lock(); values[id] = value; lock.unlock() }
    public func delete(_ id: UUID) throws { lock.lock(); values[id] = nil; lock.unlock() }
}

/// Ostatnie cztery znaki klucza — jedyne, co interfejs pokazuje po zapisie.
public func maskedKey(_ key: String) -> String {
    key.count <= 4 ? "••••" : "••••" + key.suffix(4)
}
```

`Sources/MeetNotesProviders/HTTPClient.swift`:

```swift
import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (d, r) = try await URLSession.shared.data(for: request)
        guard let h = r as? HTTPURLResponse else { throw ProviderError.badResponse("not HTTP") }
        return (d, h)
    }
}
```

`Sources/MeetNotesProviders/OpenAICompatibleClient.swift`:

```swift
import Foundation

/// Kształt wywołania ASR. ASR nie ma jednego kształtu (spec fazy 1, §4.1):
/// 47 modeli czatowych przyjmuje audio przez czat, a model transkrypcyjny
/// idzie osobnym endpointem, którego nie ma w liście modeli.
public enum ASRShape: String, Codable, Sendable, CaseIterable {
    case audioTranscriptions
    case chatAudio
}

public struct ModelInfo: Codable, Equatable, Sendable {
    public var id: String
    public var inputModalities: [String]?
    public var outputModalities: [String]?
}

public struct TranscribedWord: Codable, Equatable, Sendable {
    public var word: String
    public var start: Double
    public var end: Double
}

public struct TranscriptionResult: Codable, Equatable, Sendable {
    public var text: String
    /// `nil`, gdy kształt nie daje znaczników słów (czat).
    public var words: [TranscribedWord]?
}

/// Dialekt zgodny z OpenAI — w fazie 1 jedyny. Ollama, oMLX i LM Studio wystawiają
/// `/v1/*`, więc natywny dialekt Ollamy nie jest potrzebny (odstępstwo od §3 speca,
/// YAGNI). Transkrypcja: ciało JSON z audio w base64 — tak, jak w wywołaniu
/// z rozdz. 11 dla OpenRoutera.
public struct OpenAICompatibleClient: Sendable {
    public let provider: Provider
    public let key: String?
    public let http: any HTTPClient

    public init(provider: Provider, key: String?, http: any HTTPClient = URLSessionHTTPClient()) {
        self.provider = provider
        self.key = key
        self.http = http
    }

    func request(_ path: String, method: String = "POST", body: [String: Any]? = nil, timeout: Double = 120) throws -> URLRequest {
        var r = URLRequest(url: provider.baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = timeout
        if let key { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    func json(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await http.send(req)
        guard (200..<300).contains(resp.statusCode) else {
            throw ProviderError.http(resp.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse("not a JSON object")
        }
        return obj
    }

    public func listModels() async throws -> [ModelInfo] {
        let obj = try await json(try request("models", method: "GET", timeout: 30))
        guard let data = obj["data"] as? [[String: Any]] else { throw ProviderError.badResponse("no data[]") }
        return data.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            let arch = m["architecture"] as? [String: Any]
            return ModelInfo(id: id, inputModalities: arch?["input_modalities"] as? [String],
                             outputModalities: arch?["output_modalities"] as? [String])
        }
    }

    /// `language == nil` tylko w sondzie honorowania języka. Profil nagrania zawsze
    /// podaje język (P7).
    public func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) async throws -> TranscriptionResult {
        let audio: [String: Any] = ["data": wav.base64EncodedString(), "format": "wav"]
        switch shape {
        case .audioTranscriptions:
            var body: [String: Any] = ["model": model, "input_audio": audio, "response_format": "verbose_json",
                                       "timestamp_granularities": ["word"]]
            if let language { body["language"] = language.rawValue }
            let obj = try await json(try request("audio/transcriptions", body: body))
            guard let text = obj["text"] as? String else { throw ProviderError.badResponse("no text") }
            return TranscriptionResult(text: text, words: Self.words(obj))
        case .chatAudio:
            let instruction = language.map { "Transcribe this audio verbatim. The language is \($0.rawValue). Output only the transcript." }
                ?? "Transcribe this audio verbatim. Output only the transcript."
            let body: [String: Any] = ["model": model, "messages": [[
                "role": "user",
                "content": [["type": "text", "text": instruction], ["type": "input_audio", "input_audio": audio]],
            ]]]
            let obj = try await json(try request("chat/completions", body: body))
            return TranscriptionResult(text: try Self.chatContent(obj), words: nil)
        }
    }

    public func chat(model: String, system: String, user: String) async throws -> String {
        let body: [String: Any] = ["model": model, "messages": [["role": "system", "content": system],
                                                                ["role": "user", "content": user]]]
        return try Self.chatContent(try await json(try request("chat/completions", body: body)))
    }

    public func embed(model: String, text: String) async throws -> [Double] {
        let obj = try await json(try request("embeddings", body: ["model": model, "input": text], timeout: 30))
        guard let data = obj["data"] as? [[String: Any]], let v = data.first?["embedding"] as? [Double], !v.isEmpty else {
            throw ProviderError.badResponse("no embedding")
        }
        return v
    }

    static func chatContent(_ obj: [String: Any]) throws -> String {
        guard let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else { throw ProviderError.badResponse("no choices[0].message.content") }
        return content
    }

    static func words(_ obj: [String: Any]) -> [TranscribedWord]? {
        func parse(_ arr: [[String: Any]]) -> [TranscribedWord] {
            arr.compactMap { w in
                guard let word = w["word"] as? String, let s = (w["start"] as? NSNumber)?.doubleValue,
                      let e = (w["end"] as? NSNumber)?.doubleValue else { return nil }
                return TranscribedWord(word: word, start: s, end: e)
            }
        }
        if let top = obj["words"] as? [[String: Any]] { return parse(top) }
        if let segs = obj["segments"] as? [[String: Any]] {
            let all = segs.flatMap { ($0["words"] as? [[String: Any]]).map(parse) ?? [] }
            return all.isEmpty ? nil : all
        }
        return nil
    }
}
```

- [ ] **Krok 5: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 57/57 testów uruchomionych i zaliczonych.`

- [ ] **Krok 6: Commit.**

```bash
git add scripts/make-probe-clips.sh Sources/MeetNotesProviders Tests/MeetNotesProvidersTests
git commit -m "Dostawcy: klient OpenAI-zgodny, klucze w peku kluczy, nagrania probne" -m "Transkrypcja JSON z audio w base64 (ksztalt z rozdz. 11) i ksztalt czatowy. LanguageCode nie powstaje z auto. Blad HTTP nie niesie klucza."
```

---

### Zadanie B2: Sonda i klasyfikacja obsługi języka (P1–P3, P10)

Status: ✅ zweryfikowane (7 testów).

**Pliki:**
- Utwórz: `Sources/MeetNotesProviders/Probe.swift`
- Test: `Tests/MeetNotesProvidersTests/ProbeTests.swift`

**Interfejsy:**
- Pobiera: `OpenAICompatibleClient`, `ProbeClips`, `LanguageCode` (B1).
- Dostarcza: `Role` (`.asr`, `.correction`, `.summary`, `.embedding`), `LanguageHandling` (`.enforced`, `.filtered`, `.automatic`, `.unknown`), `ProbeResult(providerID:model:role:works:failure:shape:languageHandling:embeddingDimension:checkedAt:)` (wartości domyślne poza trzema pierwszymi), `ProbeRunner(client:)`: `probe(model:role:language:now:) async -> ProbeResult`, `classifyLanguage(model:language:) async -> LanguageHandling`.

- [ ] **Krok 1: Test, który padnie.** Utwórz `Tests/MeetNotesProvidersTests/ProbeTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesProviders

private func runner(_ http: StubHTTP, provider: Provider = openRouter) -> ProbeRunner {
    ProbeRunner(client: OpenAICompatibleClient(provider: provider, key: "k", http: http))
}

@Test func transcriptionModelTypedByHandPassesTheProbe() async {
    // P2: mai-transcribe-2 nie jest na liście modeli, a sonda go przyjmuje.
    let http = StubHTTP { path, body in
        guard path.hasSuffix("audio/transcriptions") else { return fail(404) }
        if isPolishClip(body) { return transcript("Raz, dwa, trzy.") }
        return transcript(body["language"] == nil ? "One, two, three." : "Łan tu trii.")
    }
    let r = await runner(http).probe(model: "microsoft/mai-transcribe-2", role: .asr, language: .polish)
    #expect(r.works)
    #expect(r.shape == ASRShape.audioTranscriptions)
    #expect(r.languageHandling == LanguageHandling.enforced)
}

@Test func chatOnlyModelIsRecognizedWithUnknownLanguageHandling() async {
    // P3: model działający wyłącznie przez czat.
    let http = StubHTTP { path, _ in
        path.hasSuffix("chat/completions") ? chatReply("raz, dwa, trzy") : fail(404)
    }
    let r = await runner(http).probe(model: "google/gemini-3.8-flash", role: .asr, language: .polish)
    #expect(r.works)
    #expect(r.shape == ASRShape.chatAudio)
    #expect(r.languageHandling == LanguageHandling.unknown)
}

@Test func textOnlyRuntimeFailsTheASRProbeButPassesChat() async {
    // P1 na poziomie jednostkowym: tak odpowiada Ollama — brak endpointu audio,
    // a czat grzecznie odmawia. Na żywym endpoincie: krok ręczny w planie.
    let http = StubHTTP { path, _ in
        path.hasSuffix("audio/transcriptions") ? fail(404, "404 page not found") : chatReply("I can't listen to audio, but OK.")
    }
    let ollama = Provider(name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!)
    let asr = await runner(http, provider: ollama).probe(model: "qwen3:8b", role: .asr, language: .polish)
    #expect(!asr.works)
    #expect(asr.failure?.contains("audioTranscriptions") == true)
    let chat = await runner(http, provider: ollama).probe(model: "qwen3:8b", role: .correction, language: nil)
    #expect(chat.works)
}

@Test func modelThatIgnoresLanguageIsAutomatic() async {
    // P10: ta sama odpowiedź z językiem i bez — parametr nic nie robi (profil Parakeeta przez API).
    let http = StubHTTP { _, body in transcript(isPolishClip(body) ? "raz dwa trzy" : "one two three") }
    let r = await runner(http).probe(model: "nvidia/parakeet-tdt-0.6b-v3", role: .asr, language: .polish)
    #expect(r.works)
    #expect(r.languageHandling == LanguageHandling.automatic)
}

@Test func rejectedLanguageParameterMeansAutomatic() async {
    let http = StubHTTP { _, body in
        if body["language"] != nil && !isPolishClip(body) { return fail(400, "{\"error\":\"language not supported\"}") }
        return transcript(isPolishClip(body) ? "raz dwa trzy" : "one two three")
    }
    let h = await runner(http).classifyLanguage(model: "x", language: .polish)
    #expect(h == LanguageHandling.automatic)
}

@Test func nondeterministicModelIsNotClassified() async {
    let counter = Counter()
    let http = StubHTTP { _, _ in transcript("one two three \(counter.next())") }
    let h = await runner(http).classifyLanguage(model: "x", language: .polish)
    #expect(h == LanguageHandling.unknown) // lepiej „nie wiem" niż fałszywe „wymuszony"
}

@Test func embeddingProbeRecordsDimension() async {
    let http = StubHTTP { _, _ in ok(["data": [["embedding": [0.1, 0.2, 0.3, 0.4]]]]) }
    let r = await runner(http).probe(model: "text-embedding", role: .embedding, language: nil)
    #expect(r.works)
    #expect(r.embeddingDimension == 4)
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}
```

- [ ] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesProvidersTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `ProbeRunner`, `ASRShape` w porównaniach, `LanguageHandling`.

- [ ] **Krok 3: Implementacja.** `Sources/MeetNotesProviders/Probe.swift`:

```swift
import Foundation

public enum Role: String, Codable, CaseIterable, Sendable {
    case asr, correction, summary, embedding
}

/// Co znaczy „język" w presecie dla danego modelu (spec fazy 1, §1.5).
public enum LanguageHandling: String, Codable, Sendable {
    /// Model przyjmuje język i się do niego stosuje (np. MAI-Transcribe-2).
    case enforced
    /// Model wykrywa język sam, dekoder przycina wynik (Parakeet przez FluidAudio — faza 2).
    case filtered
    /// Model wykrywa język sam i nic go nie przycina — ustawienie nie działa.
    case automatic
    /// Nie da się rozstrzygnąć: model niedeterministyczny albo kształt czatowy.
    case unknown
}

public struct ProbeResult: Codable, Equatable, Sendable {
    public var providerID: UUID
    public var model: String
    public var role: Role
    public var works: Bool
    public var failure: String?
    public var shape: ASRShape?
    public var languageHandling: LanguageHandling?
    public var embeddingDimension: Int?
    public var checkedAt: Date

    public init(providerID: UUID, model: String, role: Role, works: Bool = false, failure: String? = nil,
                shape: ASRShape? = nil, languageHandling: LanguageHandling? = nil, embeddingDimension: Int? = nil,
                checkedAt: Date = Date()) {
        self.providerID = providerID
        self.model = model
        self.role = role
        self.works = works
        self.failure = failure
        self.shape = shape
        self.languageHandling = languageHandling
        self.embeddingDimension = embeddingDimension
        self.checkedAt = checkedAt
    }
}

/// Sonda: lista to wygoda, **sonda to autorytet**, wpisanie z ręki to wyjście
/// awaryjne (spec fazy 1, §4). Nie wiemy z góry, który model co potrafi —
/// sprawdzamy żądaniem. Ollama nie przejdzie sondy ASR, bo nie umie, a nie
/// dlatego, że ktoś to wpisał w kod.
public struct ProbeRunner: Sendable {
    public let client: OpenAICompatibleClient

    public init(client: OpenAICompatibleClient) { self.client = client }

    public func probe(model: String, role: Role, language: LanguageCode?, now: Date = Date()) async -> ProbeResult {
        var r = ProbeResult(providerID: client.provider.id, model: model, role: role, checkedAt: now)
        switch role {
        case .asr:
            let lang = language ?? .english
            let clip = ProbeClips.clip(for: lang) ?? ProbeClips.english
            let langParam: LanguageCode? = clip.language == lang ? lang : nil
            var failures: [String] = []
            for shape in ASRShape.allCases {
                do {
                    let t = try await client.transcribe(wav: clip.wav, model: model, language: langParam, shape: shape)
                    if ProbeClips.matches(t.text, clip) {
                        r.works = true
                        r.shape = shape
                        r.languageHandling = shape == .chatAudio ? .unknown : await classifyLanguage(model: model, language: lang)
                        return r
                    }
                    failures.append("\(shape.rawValue): unexpected text \"\(t.text.prefix(60))\"")
                } catch {
                    failures.append("\(shape.rawValue): \(error)")
                }
            }
            r.failure = failures.joined(separator: "; ")
        case .correction, .summary:
            do {
                let reply = try await client.chat(model: model, system: "You are a connectivity probe. Reply with OK.", user: "ping")
                r.works = !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !r.works { r.failure = "empty reply" }
            } catch { r.failure = "\(error)" }
        case .embedding:
            do {
                let v = try await client.embed(model: model, text: "probe")
                r.works = true
                r.embeddingDimension = v.count
            } catch { r.failure = "\(error)" }
        }
        return r
    }

    /// Sonda honorowania języka (P10). Nagranie w **innym** języku niż preset:
    /// A — z językiem presetu, B1 i B2 — bez. Na nagraniu w języku presetu wszystkie
    /// trzy dałyby to samo i model z działającym parametrem wyglądałby na
    /// „automatyczny". B1 ≠ B2 → model niedeterministyczny → nie rozstrzygamy.
    public func classifyLanguage(model: String, language: LanguageCode) async -> LanguageHandling {
        let clip = ProbeClips.mismatched(for: language)
        guard let b1 = try? await client.transcribe(wav: clip.wav, model: model, language: nil, shape: .audioTranscriptions),
              let b2 = try? await client.transcribe(wav: clip.wav, model: model, language: nil, shape: .audioTranscriptions) else {
            return .unknown
        }
        guard ProbeClips.normalize(b1.text) == ProbeClips.normalize(b2.text) else { return .unknown }
        guard let a = try? await client.transcribe(wav: clip.wav, model: model, language: language, shape: .audioTranscriptions) else {
            return .automatic // parametr języka odrzucony: ustawienia nie da się wymusić
        }
        return ProbeClips.normalize(a.text) == ProbeClips.normalize(b1.text) ? .automatic : .enforced
    }
}
```

- [ ] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 64/64 testów uruchomionych i zaliczonych.`

- [ ] **Krok 5: Mutacja (P10).** W `classifyLanguage` zamień ostatnią linię `return ProbeClips.normalize(a.text) == ProbeClips.normalize(b1.text) ? .automatic : .enforced` na `return .enforced`. `scripts/test.sh --filter modelThatIgnoresLanguageIsAutomatic` — oczekiwane: pada. Przywróć; `64/64`.

- [ ] **Krok 6: Commit.**

```bash
git add Sources/MeetNotesProviders Tests/MeetNotesProvidersTests
git commit -m "Dostawcy: sonda per rola i klasyfikacja obslugi jezyka" -m "Sonda ASR probuje obu ksztaltow wywolania. Honorowanie jezyka sprawdzane nagraniem w innym jezyku niz preset: A z jezykiem, B1 i B2 bez. Model niedeterministyczny - nie wiadomo, nigdy falszywe wymuszony."
```

---

### Zadanie B3: Presety, ustawienia globalne, zapis na dysk (P7, P13)

Status: ✅ zweryfikowane (7 testów, w tym przeniesiony z B1).

**Pliki:**
- Utwórz: `Sources/MeetNotesProviders/Preset.swift`, `Sources/MeetNotesProviders/Stores.swift`
- Test: `Tests/MeetNotesProvidersTests/PresetTests.swift`

**Interfejsy:**
- Pobiera: `LanguageCode`, `Provider` (B1), `ProbeResult`, `Role` (B2).
- Dostarcza: `RoleAssignment(providerID:model:prompt:)`, `Preset(id:name:language:asr:correction:summary:notesLanguage:)` z `effectiveNotesLanguage` i `validate() throws`, `PresetError.missingName`, `.missingLanguage`, `.missingASR`, `GlobalSettings(embedding:defaultPresetID:)`, `ProbeCache` (`record(_:)`, `result(provider:model:role:)`). `MeetNotesPaths(root:)`, `MeetNotesPaths.fromEnvironment(_:)` (`MEETNOTES_DATA_DIR`), `providers`, `presets`, `settings`, `probeCache`, `sessions`. `JSONFile.load(_:from:default:) throws`, `JSONFile.save(_:to:) throws`. `PresetsFile` z `upsert(_:) throws`, `ProvidersFile`.

- [ ] **Krok 1: Test, który padnie.** Utwórz `Tests/MeetNotesProvidersTests/PresetTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetNotesProviders

private let asr = RoleAssignment(providerID: UUID(), model: "microsoft/mai-transcribe-2")

@Test func autoLanguageCannotBeConstructed() {
    // 🔴 „Nigdy auto" egzekwowane typem.
    #expect(throws: LanguageCodeError.autoIsForbidden) { _ = try LanguageCode("auto") }
    #expect(throws: LanguageCodeError.autoIsForbidden) { _ = try JSONDecoder().decode(LanguageCode.self, from: Data("\"AUTO\"".utf8)) }
    #expect(throws: LanguageCodeError.empty) { _ = try LanguageCode(" ") }
}

@Test func presetWithoutLanguageCannotBeSaved() {
    // P7: bramka, nie ostrzeżenie.
    var file = PresetsFile()
    #expect(throws: PresetError.missingLanguage) { try file.upsert(Preset(name: "Polish", language: nil, asr: asr)) }
    #expect(file.presets.isEmpty)
}

@Test func completePresetIsSavedAndReplacedById() throws {
    var file = PresetsFile()
    var p = Preset(name: "Polish", language: .polish, asr: asr)
    try file.upsert(p)
    p.name = "Polish (MAI)"
    try file.upsert(p)
    #expect(file.presets.count == 1)
    #expect(file.presets[0].name == "Polish (MAI)")
}

@Test func notesLanguageDefaultsToPresetLanguage() {
    #expect(Preset(name: "Polish", language: .polish, asr: asr).effectiveNotesLanguage == .polish)
    #expect(Preset(name: "Polish", language: .polish, asr: asr, notesLanguage: .english).effectiveNotesLanguage == .english)
}

@Test func storesRoundTripThroughDisk() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    let paths = MeetNotesPaths(root: root)
    var cache = ProbeCache()
    cache.record(ProbeResult(providerID: asr.providerID, model: asr.model, role: .asr, works: true, failure: nil,
                             shape: .audioTranscriptions, languageHandling: .enforced, embeddingDimension: nil,
                             checkedAt: Date(timeIntervalSince1970: 1_000)))
    try JSONFile.save(cache, to: paths.probeCache)
    let back = try JSONFile.load(ProbeCache.self, from: paths.probeCache, default: ProbeCache())
    #expect(back.result(provider: asr.providerID, model: asr.model, role: .asr)?.languageHandling == .enforced)
    #expect(try JSONFile.load(PresetsFile.self, from: paths.presets, default: PresetsFile()).presets.isEmpty)
}

@Test func dataDirectoryFollowsEnvironment() {
    #expect(MeetNotesPaths.fromEnvironment(["MEETNOTES_DATA_DIR": "/tmp/x/.devdata"]).root.path == "/tmp/x/.devdata")
}

@Test func providerFileNeverContainsAKey() throws {
    // P8 (przeniesione z B1 — Hermes 2.2: używa ProvidersFile z tego zadania): klucz nie jest polem struktury dostawcy — nie może trafić do pliku.
    let json = String(decoding: try JSONEncoder().encode(ProvidersFile(providers: [openRouter])), as: UTF8.self)
    #expect(!json.lowercased().contains("key"))
    #expect(maskedKey("sk-or-v1-abcdef1234") == "••••1234")
}
```

- [ ] **Krok 2: Uruchom i sprawdź, że pada.** `scripts/test.sh --filter MeetNotesProvidersTests` — oczekiwane: kod `1`, `cannot find … in scope` dla `RoleAssignment`, `Preset`, `PresetsFile`, `MeetNotesPaths`.

- [ ] **Krok 3: Implementacja.**

`Sources/MeetNotesProviders/Preset.swift`:

```swift
import Foundation

public struct RoleAssignment: Codable, Equatable, Sendable {
    public var providerID: UUID
    public var model: String
    public var prompt: String?

    public init(providerID: UUID, model: String, prompt: String? = nil) {
        self.providerID = providerID
        self.model = model
        self.prompt = prompt
    }
}

public enum PresetError: Error, Equatable {
    case missingName
    /// P7: bramka, nie ostrzeżenie.
    case missingLanguage
    case missingASR
}

/// Nazwany zestaw: język + ASR + korekta + podsumowanie (spec fazy 1, §1.5).
/// 🔴 Bez embeddingu — ten jest globalny (`GlobalSettings`), bo wektory
/// z różnych modeli nie są porównywalne.
public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Opcjonalny tylko w trakcie edycji. `validate()` nie przepuści `nil`.
    public var language: LanguageCode?
    public var asr: RoleAssignment?
    public var correction: RoleAssignment?
    public var summary: RoleAssignment?
    /// `nil` = jak język presetu (kopia jawnego wyboru, nie wykrywanie — §1.4).
    public var notesLanguage: LanguageCode?

    public init(id: UUID = UUID(), name: String, language: LanguageCode?, asr: RoleAssignment?,
                correction: RoleAssignment? = nil, summary: RoleAssignment? = nil, notesLanguage: LanguageCode? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.asr = asr
        self.correction = correction
        self.summary = summary
        self.notesLanguage = notesLanguage
    }

    public var effectiveNotesLanguage: LanguageCode? { notesLanguage ?? language }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PresetError.missingName }
        guard language != nil else { throw PresetError.missingLanguage }
        guard asr != nil else { throw PresetError.missingASR }
    }
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    /// Jeden model embeddingu dla całego archiwum (P13).
    public var embedding: RoleAssignment?
    public var defaultPresetID: UUID?

    public init(embedding: RoleAssignment? = nil, defaultPresetID: UUID? = nil) {
        self.embedding = embedding
        self.defaultPresetID = defaultPresetID
    }
}

public struct ProbeCache: Codable, Equatable, Sendable {
    public var results: [String: ProbeResult] = [:]

    public init() {}

    static func key(_ provider: UUID, _ model: String, _ role: Role) -> String {
        "\(provider.uuidString)|\(model)|\(role.rawValue)"
    }

    public mutating func record(_ r: ProbeResult) { results[Self.key(r.providerID, r.model, r.role)] = r }

    public func result(provider: UUID, model: String, role: Role) -> ProbeResult? {
        results[Self.key(provider, model, role)]
    }
}
```

`Sources/MeetNotesProviders/Stores.swift`:

```swift
import Foundation

/// Katalog danych. Zmienna `MEETNOTES_DATA_DIR` przestawia go na katalog w repo
/// na czas prac (`.devdata/`, spec rdzenia §8 — czysto na dysku).
public struct MeetNotesPaths: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> MeetNotesPaths {
        if let dir = env["MEETNOTES_DATA_DIR"], !dir.isEmpty { return MeetNotesPaths(root: URL(fileURLWithPath: dir)) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MeetNotesPaths(root: base.appendingPathComponent("MeetNotes"))
    }

    public var providers: URL { root.appendingPathComponent("providers.json") }
    public var presets: URL { root.appendingPathComponent("presets.json") }
    public var settings: URL { root.appendingPathComponent("settings.json") }
    public var probeCache: URL { root.appendingPathComponent("probe-cache.json") }
    public var sessions: URL { root.appendingPathComponent("sessions") }
}

public enum JSONFile {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Brak pliku → wartość domyślna. Uszkodzony plik → błąd (nie kasujemy cudzych danych).
    public static func load<T: Decodable>(_ type: T.Type, from url: URL, default value: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return value }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

public struct PresetsFile: Codable, Equatable, Sendable {
    public var presets: [Preset] = []
    public init(presets: [Preset] = []) { self.presets = presets }

    /// Zapis przez walidację — P7 na poziomie magazynu, nie tylko formularza.
    public mutating func upsert(_ p: Preset) throws {
        try p.validate()
        if let i = presets.firstIndex(where: { $0.id == p.id }) { presets[i] = p } else { presets.append(p) }
    }
}

public struct ProvidersFile: Codable, Equatable, Sendable {
    public var providers: [Provider] = []
    public init(providers: [Provider] = []) { self.providers = providers }
}
```

- [ ] **Krok 4: Uruchom całość.** `scripts/test.sh` — oczekiwane: `test.sh: 71/71 testów uruchomionych i zaliczonych.`

- [ ] **Krok 5: Mutacja (P7).** W `PresetsFile.upsert` usuń linię `try p.validate()`. `scripts/test.sh --filter presetWithoutLanguageCannotBeSaved` — oczekiwane: pada. Przywróć; `71/71`.

- [ ] **Krok 6: Commit.**

```bash
git add Sources/MeetNotesProviders Tests/MeetNotesProvidersTests
git commit -m "Dostawcy: presety z jezykiem obowiazkowym, embedding globalny" -m "Walidacja w magazynie, nie tylko w formularzu (P7). Embedding poza presetem, bo wektory z roznych modeli nie sa porownywalne (P13). Katalog danych z MEETNOTES_DATA_DIR."
```

---

### Zadanie B4: CLI — lista modeli i sonda

Status: 🔧 pełny CLI skompilowany przebiegiem kontrolnym 2026-09-25 (kopia spike'a, Sonnet); wersja pośrednia po B4 nie była kompilowana osobno. Funkcje `client`, `models`, `probe` są słowo w słowo z `CLI.swift` ze spike'a (🔧 skompilowany). Nowe jest tylko ich wpięcie w plik z A9.

**Pliki:**
- Zmień: `Sources/meetnotes-cli/CLI.swift`

**Interfejsy:**
- Pobiera: `OpenAICompatibleClient`, `ProbeRunner`, `Role`, `LanguageCode` (B1–B2); `CLI.option`, `CLI.positional` (A9).
- Dostarcza: `meetnotes-cli models <baseURL>`, `probe <baseURL> <model> <asr|correction|summary|embedding> [--language pl]`, `CLI.client(_:)` (używane w C4). Klucz ze zmiennej `MEETNOTES_API_KEY`.

- [ ] **Krok 1: Import.** Pod `import Foundation` dopisz `import MeetNotesProviders`.

- [ ] **Krok 2: Pomoc.** W `usage`, pod linią `check-system-audio`, dopisz:

```text
      models <baseURL>                                            lista modeli (klucz: MEETNOTES_API_KEY)
      probe <baseURL> <model> <asr|correction|summary|embedding> [--language pl]
```

- [ ] **Krok 3: Polecenia.** W `switch cmd`, pod `case "check-system-audio": …`, dopisz:

```swift
            case "models": try await models(args)
            case "probe": try await probe(args)
```

- [ ] **Krok 4: Funkcje.** Przed ostatnim `}` struktury `CLI` dopisz:

```swift
    static func client(_ base: String) throws -> OpenAICompatibleClient {
        guard let url = URL(string: base) else { throw ProviderError.badResponse("zły adres \(base)") }
        return OpenAICompatibleClient(provider: Provider(name: "cli", baseURL: url),
                                      key: ProcessInfo.processInfo.environment["MEETNOTES_API_KEY"])
    }

    static func models(_ args: [String]) async throws {
        for m in try await client(try positional(args, 0)).listModels() {
            print(m.id + (m.inputModalities.map { "  [\($0.joined(separator: ","))]" } ?? ""))
        }
    }

    static func probe(_ args: [String]) async throws {
        guard let role = Role(rawValue: try positional(args, 2)) else { print(usage); exit(64) }
        let lang = try option(args, "--language").map { try LanguageCode($0) }
        let r = await ProbeRunner(client: try client(try positional(args, 0))).probe(model: try positional(args, 1), role: role, language: lang)
        print(r.works ? "DZIAŁA" : "NIE DZIAŁA", r.shape?.rawValue ?? "", r.languageHandling?.rawValue ?? "",
              r.embeddingDimension.map { "wymiar \($0)" } ?? "", r.failure ?? "")
    }
```

- [ ] **Krok 5: Zbuduj i sprawdź bez sieci.** `swift build --product meetnotes-cli` — oczekiwane: `Build complete!`. `swift run meetnotes-cli probe http://127.0.0.1:9/v1 x asr` — oczekiwane: `NIE DZIAŁA` z opisem błędu połączenia dla obu kształtów.

- [ ] **Krok 6: Pełne testy.** `scripts/test.sh` — oczekiwane: `76/76` (po E2).

- [ ] **Krok 7: Commit.**

```bash
git add Sources/meetnotes-cli
git commit -m "CLI: models i probe"
```

---

### Zadanie B5: Sondy na żywo (bramka G3)

Status: nigdy niewykonane. **Wymaga klucza OpenRoutera użytkownika** i kosztuje grosze (każda sonda ASR to 1–4 żądania po ~2 s audio przy 0,10 USD/h). Klucz ustawia użytkownik w swoim terminalu: `export MEETNOTES_API_KEY=…`. Wykonawca go nie widzi i nie wpisuje.

**Pliki:**
- Utwórz: `docs/superpowers/spikes/2026-09-24-g3-sondy-na-zywo.md` — polecenia i wyniki.

- [ ] **Krok 1: Katalog kłamie przez przemilczenie.** `B=$(swift build --show-bin-path)/meetnotes-cli`, potem `$B models https://openrouter.ai/api/v1 | wc -l` (📐 było 458) i `$B models https://openrouter.ai/api/v1 | grep -c mai-transcribe` — oczekiwane: `0`.

- [ ] **Krok 2: P2 — model wpisany z ręki.** `$B probe https://openrouter.ai/api/v1 microsoft/mai-transcribe-2 asr --language pl` — oczekiwane: `DZIAŁA audioTranscriptions enforced`. **STOP, jeśli `NIE DZIAŁA`** z błędem formatu żądania (np. 400 o `input_audio`): założenie o ciele JSON z rozdz. 11 jest błędne i trzeba przejść na `multipart/form-data`. To zmiana planu C, więc decyzja użytkownika.

- [ ] **Krok 3: P10 — Parakeet przez API.** `$B probe https://openrouter.ai/api/v1 nvidia/parakeet-tdt-0.6b-v3 asr --language pl` — hipoteza ze speca: `DZIAŁA audioTranscriptions automatic`. Zapisz wynik bez względu na to, jaki jest. To pomiar, nie test do zaliczenia.

- [ ] **Krok 4: P3 — model tylko czatowy.** `$B probe https://openrouter.ai/api/v1 google/gemini-3.8-flash asr --language pl` — oczekiwane: `DZIAŁA chatAudio unknown`.

- [ ] **Krok 5: P1 — Ollama na żywo (jeśli zainstalowana).** `ollama list`, potem dla jednego modelu tekstowego `$B probe http://localhost:11434/v1 <model> asr --language pl` — oczekiwane `NIE DZIAŁA` — i `$B probe http://localhost:11434/v1 <model> correction` — oczekiwane `DZIAŁA`. Bez Ollamy krok pomiń i zanotuj.

- [ ] **Krok 6: Klucz nie wycieka do plików (P8).** `grep -rlF -- "$MEETNOTES_API_KEY" . ~/Library/Application\ Support/MeetNotes 2>/dev/null | grep -v '^./.build'` — oczekiwane: pusto (polecenie wypisuje tylko nazwy plików, nie klucz). Zapis i odczyt z pęku kluczy sprawdza D3 przez aplikację.

- [ ] **Krok 7: Zapisz wyniki i commit.**

```bash
git add docs/superpowers/spikes
git commit -m "Sondy na zywo: OpenRouter, Parakeet przez API, Ollama"
```
