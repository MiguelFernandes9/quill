import Foundation

/// The background pattern drawn behind a pad's ink. Not part of the PKDrawing —
/// it travels with the sketch metadata, so it syncs like any other property.
enum PaperStyle: String, Codable, CaseIterable, Equatable {
    case blank
    case lines
    case grid
    case dots

    var label: String {
        switch self {
        case .blank: return "Blank"
        case .lines: return "Lines"
        case .grid: return "Grid"
        case .dots: return "Dots"
        }
    }

    var symbolName: String {
        switch self {
        case .blank: return "rectangle"
        case .lines: return "text.justify"
        case .grid: return "squareshape.split.3x3"
        case .dots: return "circle.grid.3x3"
        }
    }
}
