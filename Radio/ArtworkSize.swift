import CoreGraphics

enum ArtworkSize: String, CaseIterable {
    case small, medium, large

    var dimension: CGFloat {
        switch self {
        case .small: 66
        case .medium: 80
        case .large: 120
        }
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}
