// Weryfikacja podpisu EdDSA Sparkle (TASK-99): ed25519-verify.swift <klucz publiczny base64> <podpis base64> <plik>.
// Kod 0 = podpis pasuje, 1 = nie pasuje, 2 = złe argumenty. Bez dostępu do pęku.
import CryptoKit
import Foundation

let a = CommandLine.arguments
guard a.count == 4, let key = Data(base64Encoded: a[1]), let sig = Data(base64Encoded: a[2]),
      let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
      let data = FileManager.default.contents(atPath: a[3]) else { exit(2) }
exit(pub.isValidSignature(sig, for: data) ? 0 : 1)
