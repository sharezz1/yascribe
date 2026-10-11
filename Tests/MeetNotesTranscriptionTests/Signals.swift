import Foundation
import MeetNotesSessionFormat

let ns = Timebase(numer: 1, denom: 1)

func tone(seconds: Double, rate: Double, hz: Double = 300, amp: Double = 0.3) -> [Int16] {
    (0..<Int(seconds * rate)).map { Int16(amp * 32_767 * sin(2 * .pi * hz * Double($0) / rate)) }
}

func silence(seconds: Double, rate: Double, channels: Int = 1) -> [Int16] {
    [Int16](repeating: 0, count: Int(seconds * rate) * channels)
}

/// Nagranie ze „słowami": ton 2 s co 10 s, zaczynając od 5 s.
func burstTrack(seconds: Double, rate: Double) -> (samples: [Int16], starts: [Double]) {
    var s: [Int16] = []
    var starts: [Double] = []
    var t = 0.0
    while t + 10 <= seconds {
        s += silence(seconds: 5, rate: rate); starts.append(t + 5)
        s += tone(seconds: 2, rate: rate); s += silence(seconds: 3, rate: rate)
        t += 10
    }
    return (s, starts)
}
