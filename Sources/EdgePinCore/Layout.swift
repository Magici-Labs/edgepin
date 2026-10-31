import CoreGraphics

public enum Edge: String, CaseIterable {
    // Order matters: left and right strips run the full height of the screen and
    // top and bottom fit between them, so the sides are handled first.
    case left, right, top, bottom

    public var isSide: Bool { self == .left || self == .right }
    public var title: String { rawValue.capitalized }
}

/// The strips pinned windows hold on one screen, and where other windows have to
/// go to stay out of them.
///
/// Rects are in Accessibility coordinates: the origin is the top-left corner of
/// the main display and y grows downward.
public struct Layout {
    /// The screen's visible frame, without the menu bar and the Dock.
    public var visible: CGRect
    /// Strip thickness for each edge that has a pin showing on this screen.
    public var thickness: [Edge: CGFloat]

    /// A window squeezed by a strip keeps at least this much width or height;
    /// below that it is moved out of the strip instead of trimmed.
    public static let minKept: CGFloat = 160
    public static let minThickness: CGFloat = 120

    public init(visible: CGRect, thickness: [Edge: CGFloat] = [:]) {
        self.visible = visible
        self.thickness = thickness
    }

    /// What is left of the screen once every strip is taken out.
    public var free: CGRect {
        var r = visible
        if let t = thickness[.left] { r.origin.x += t; r.size.width -= t }
        if let t = thickness[.right] { r.size.width -= t }
        if let t = thickness[.top] { r.origin.y += t; r.size.height -= t }
        if let t = thickness[.bottom] { r.size.height -= t }
        return r
    }

    /// The strip for an edge, which is also the frame its pinned window snaps to.
    public func strip(_ edge: Edge) -> CGRect? {
        guard let t = thickness[edge] else { return nil }
        let v = visible
        let l = thickness[.left] ?? 0, r = thickness[.right] ?? 0
        switch edge {
        case .left: return CGRect(x: v.minX, y: v.minY, width: t, height: v.height)
        case .right: return CGRect(x: v.maxX - t, y: v.minY, width: t, height: v.height)
        case .top: return CGRect(x: v.minX + l, y: v.minY, width: v.width - l - r, height: t)
        case .bottom: return CGRect(x: v.minX + l, y: v.maxY - t, width: v.width - l - r, height: t)
        }
    }

    public func overlaps(_ frame: CGRect) -> Bool {
        Edge.allCases.contains { edge in strip(edge).map { Self.overlap(frame, $0) } ?? false }
    }

    /// Where a window goes to stay clear of every strip. Only the sides that
    /// overlap a strip move; a window mostly inside one is moved out of it whole.
    /// With shiftOnly it is always moved, for apps that refuse to get smaller.
    public func squeeze(_ frame: CGRect, shiftOnly: Bool = false) -> CGRect {
        var r = frame
        let free = self.free
        for edge in Edge.allCases {
            guard let s = strip(edge), Self.overlap(r, s) else { continue }
            switch edge {
            case .left:
                if shiftOnly || r.maxX - free.minX < Self.minKept {
                    r.size.width = min(r.width, free.width)
                } else {
                    r.size.width = r.maxX - free.minX
                }
                r.origin.x = free.minX
            case .right:
                if shiftOnly || free.maxX - r.minX < Self.minKept {
                    r.size.width = min(r.width, free.width)
                    r.origin.x = free.maxX - r.width
                } else {
                    r.size.width = free.maxX - r.minX
                }
            case .top:
                if shiftOnly || r.maxY - free.minY < Self.minKept {
                    r.size.height = min(r.height, free.height)
                } else {
                    r.size.height = r.maxY - free.minY
                }
                r.origin.y = free.minY
            case .bottom:
                if shiftOnly || free.maxY - r.minY < Self.minKept {
                    r.size.height = min(r.height, free.height)
                    r.origin.y = free.maxY - r.height
                } else {
                    r.size.height = free.maxY - r.minY
                }
            }
        }
        return r
    }

    /// The edge a window is closest to, going by which side of the screen its
    /// centre is on. Plain distance to the edges would pick top for most
    /// windows, since they sit right under the menu bar.
    public static func nearestEdge(of frame: CGRect, in visible: CGRect) -> Edge {
        let dx = (frame.midX - visible.midX) / visible.width
        let dy = (frame.midY - visible.midY) / visible.height
        if abs(dx) >= abs(dy) { return dx < 0 ? .left : .right }
        return dy < 0 ? .top : .bottom
    }

    /// How far a window's outer side is from the screen edge it is pinned to.
    public static func offset(of frame: CGRect, from edge: Edge, in visible: CGRect) -> CGFloat {
        switch edge {
        case .left: return abs(frame.minX - visible.minX)
        case .right: return abs(visible.maxX - frame.maxX)
        case .top: return abs(frame.minY - visible.minY)
        case .bottom: return abs(visible.maxY - frame.maxY)
        }
    }

    public static func thickness(of frame: CGRect, edge: Edge) -> CGFloat {
        edge.isSide ? frame.width : frame.height
    }

    public static func clampThickness(_ t: CGFloat, edge: Edge, in visible: CGRect) -> CGFloat {
        let span = edge.isSide ? visible.width : visible.height
        return min(max(t, minThickness), span * 0.8)
    }

    /// The strip a newly pinned window gets: its current width (or height), or a
    /// third of the screen when it was nearly filling it.
    public static func initialThickness(of frame: CGRect, edge: Edge, in visible: CGRect) -> CGFloat {
        let span = edge.isSide ? visible.width : visible.height
        let size = thickness(of: frame, edge: edge)
        return clampThickness(size > span * 0.7 ? span / 3 : size, edge: edge, in: visible)
    }

    /// Touching edges don't count: a window right next to a strip is fine.
    static func overlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        return !i.isNull && i.width > 1 && i.height > 1
    }
}

extension CGRect {
    public func isClose(to other: CGRect, within d: CGFloat = 1.5) -> Bool {
        abs(minX - other.minX) <= d && abs(minY - other.minY) <= d
            && abs(width - other.width) <= d && abs(height - other.height) <= d
    }
}
