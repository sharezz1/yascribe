import CoreGraphics

/// Położenie pływającej pigułki: środek dolnej krawędzi stoi w miejscu przy zmianie rozmiaru (zwinięta ↔ rozwinięta),
/// okno jest wsuwane w `visibleFrame` ekranu. Czysta funkcja — bez AppKit, żeby dało się ją testować.
public enum PillPlacement {
    /// Ramka o rozmiarze `size` ze środkiem dolnej krawędzi w `bottomCenter`, wsunięta w ten z `screens`
    /// (ramki widoczne), z którym ma największą część wspólną; brak części wspólnej → pierwszy (główny).
    /// Okno większe od ekranu przykleja się do lewej/dolnej krawędzi.
    public static func frame(size: CGSize, bottomCenter: CGPoint, screens: [CGRect]) -> CGRect {
        let f = CGRect(x: bottomCenter.x - size.width / 2, y: bottomCenter.y, width: size.width, height: size.height)
        func area(_ r: CGRect) -> CGFloat { let i = r.intersection(f); return i.isNull ? 0 : i.width * i.height }
        guard let best = screens.max(by: { area($0) < area($1) }) else { return f }
        var r = f
        r.origin.x = min(max(r.minX, best.minX), max(best.minX, best.maxX - r.width))
        r.origin.y = min(max(r.minY, best.minY), max(best.minY, best.maxY - r.height))
        return r
    }
}
