import CoreGraphics
import Foundation

/// Geometry for the mixtape grid shown below Stream 2 in the panel. Single source
/// of truth for column count and tile size, shared by `MixtapeGridView` and
/// `AppDelegate.panelSize`. If these numbers move, the hand-computed panel height
/// must move with them (see `AppDelegate.panelSize`).
enum MixtapeGrid {
    /// Card content width — must match `ContentView`'s `.frame(width: 280)`.
    static let cardWidth: CGFloat = 280
    /// Matches `ChannelRow`'s `.padding(.horizontal, 14)`.
    static let horizontalPadding: CGFloat = 14
    static let interitemSpacing: CGFloat = 6
    static let rowSpacing: CGFloat = 6
    static let sectionTopPadding: CGFloat = 8
    static let sectionBottomPadding: CGFloat = 8

    /// Columns per row for a given number of enabled mixtapes: 3 for counts of
    /// 3/6/9, 5 for counts of 5/10, otherwise 4.
    static func columns(for count: Int) -> Int {
        switch count {
        case 3, 6, 9: return 3
        case 5, 10: return 5
        default: return 4
        }
    }

    static func rows(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        return Int((Double(count) / Double(columns)).rounded(.up))
    }

    /// Square edge of each tile, in points, for a given column count.
    static func tileEdge(columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        let available = cardWidth - horizontalPadding * 2
            - interitemSpacing * CGFloat(columns - 1)
        return (available / CGFloat(columns)).rounded(.down)
    }

    /// Total height the mixtape section adds to the panel, including its top
    /// `Divider()`. Zero when nothing is enabled.
    static func sectionHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let cols = columns(for: count)
        let rowCount = rows(count: count, columns: cols)
        let edge = tileEdge(columns: cols)
        return 1 // top Divider
            + sectionTopPadding
            + CGFloat(rowCount) * edge
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
            + sectionBottomPadding
    }
}
