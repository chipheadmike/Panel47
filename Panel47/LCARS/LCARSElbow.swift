import SwiftUI

/// The signature LCARS corner piece: two perpendicular arms of uniform thickness
/// joined by a swept, concentric-radius curve on the outer corner.
struct LCARSElbow: Shape {
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    var corner: Corner
    var armThickness: CGFloat = 48
    var outerRadius: CGFloat = 90

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let t = min(armThickness, w, h)
        let r = min(max(outerRadius, t), w, h)

        let base = Self.topLeftPath(w: w, h: h, t: t, r: r)

        var transform = CGAffineTransform.identity
        switch corner {
        case .topLeft:
            break
        case .topRight:
            transform = CGAffineTransform(scaleX: -1, y: 1).concatenating(.init(translationX: w, y: 0))
        case .bottomLeft:
            transform = CGAffineTransform(scaleX: 1, y: -1).concatenating(.init(translationX: 0, y: h))
        case .bottomRight:
            transform = CGAffineTransform(scaleX: -1, y: -1).concatenating(.init(translationX: w, y: h))
        }

        return base.applying(transform).applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    /// Vertical arm along the left edge, horizontal arm along the top edge, both
    /// extending to the rect's far edges with flat (unrounded) ends, joined at the
    /// top-left by concentric arcs of radius `r` (outer) and `r - t` (inner).
    private static func topLeftPath(w: CGFloat, h: CGFloat, t: CGFloat, r: CGFloat) -> Path {
        var p = Path()
        let center = CGPoint(x: r, y: r)

        p.move(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: r, y: 0))
        p.addArc(center: center, radius: r, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: t, y: h))
        p.addLine(to: CGPoint(x: t, y: r))
        p.addArc(center: center, radius: max(r - t, 0), startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: w, y: t))
        p.closeSubpath()
        return p
    }
}
