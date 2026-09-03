import SwiftUI
import ImageIO
import CoreGraphics

/// Remote artwork that is downsampled with ImageIO *at decode time* so the bitmap
/// handed to SwiftUI is already close to its on-screen pixel size.
///
/// `AsyncImage` decodes NTS artwork at its full resolution and lets the compositor
/// squash it into the ~66–120pt row in a single filtering pass. On a non-Retina
/// display that is a >10× downscale, which aliases badly ("crunchy", like
/// nearest-neighbour). A multi-step `CGImageSourceCreateThumbnailAtIndex` downscale
/// avoids that, and drops resident memory from a few MB per decoded image to a few KB.
struct ArtworkImage: View {
    let url: URL
    /// Target square edge, in points. The image is drawn `.fill` and clipped, so
    /// the downsample keeps the *shorter* pixel edge ≥ `dimension * displayScale` —
    /// NTS art is often wider than tall (e.g. 800×450), and `picture_medium` caps
    /// the *width*, so sizing by the short edge is what guarantees full coverage.
    let dimension: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: Image?

    var body: some View {
        // `.task` has to hang off a view that actually renders — an empty `Group`
        // (the state while `image == nil`) never "appears", so the load never starts.
        // `Color.clear` always lays out at the caller's frame.
        Color.clear
            .overlay {
                if let image {
                    image
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fill)
                }
            }
            .task(id: RequestKey(url: url, edge: dimension * displayScale)) {
                image = await ArtworkThumbnailCache.shared.thumbnail(
                    for: url,
                    fittingSquareEdge: dimension * displayScale
                )
            }
    }

    private struct RequestKey: Equatable {
        let url: URL
        let edge: CGFloat
    }
}

/// Serialises artwork downloads + downsamples and memoises the results.
actor ArtworkThumbnailCache {
    static let shared = ArtworkThumbnailCache()

    private final class Box: Sendable { let image: CGImage; init(_ image: CGImage) { self.image = image } }

    private let cache = NSCache<NSString, Box>()
    private var inFlight: [String: Task<Box?, Never>] = [:]

    /// Returns a downsampled image whose shorter edge is at least `edge` pixels.
    /// Concurrent calls for the same URL + size share one download.
    func thumbnail(for url: URL, fittingSquareEdge edge: CGFloat) async -> Image? {
        let shortEdgePixels = max(1, Int(edge.rounded(.up)))
        let key = "\(url.absoluteString)|\(shortEdgePixels)"

        if let box = cache.object(forKey: key as NSString) {
            return Image(decorative: box.image, scale: 1)
        }

        let task = inFlight[key] ?? {
            let task = Task<Box?, Never> {
                guard let cg = await Self.downsample(url: url, shortEdgePixels: shortEdgePixels) else {
                    return nil
                }
                return Box(cg)
            }
            inFlight[key] = task
            return task
        }()

        let box = await task.value
        inFlight[key] = nil
        if let box { cache.setObject(box, forKey: key as NSString) }
        return box.map { Image(decorative: $0.image, scale: 1) }
    }

    private static func downsample(url: URL, shortEdgePixels: Int) async -> CGImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return decode(data: data, shortEdgePixels: shortEdgePixels)
    }

    private static func decode(data: Data, shortEdgePixels: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        // The thumbnail API sizes by the LONGER edge, but we fill a square from the
        // SHORTER edge — so read the real pixel dimensions and scale the request up
        // by the aspect ratio. Never ask for more pixels than the source has.
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? shortEdgePixels
        let pixelHeight = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? shortEdgePixels
        let shortEdge = max(1, min(pixelWidth, pixelHeight))
        let longEdge = max(1, max(pixelWidth, pixelHeight))

        let target = Int((Double(shortEdgePixels) * Double(longEdge) / Double(shortEdge)).rounded(.up))
        let maxPixelSize = min(longEdge, max(1, target))

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
