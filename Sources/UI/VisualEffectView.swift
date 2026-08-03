import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    /// Round the material. A behind-window visual-effect material ignores
    /// `layer.cornerRadius`/`masksToBounds` (and an ancestor's corner mask), so
    /// its square corners bleed out behind the rounded popover window. The
    /// canonical fix is a resizable rounded-rect `maskImage`.
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        view.roundedMask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.roundedMask(cornerRadius: cornerRadius)
    }
}

extension NSVisualEffectView {
    /// Mask the material to a rounded rectangle. `cornerRadius <= 0` clears it.
    func roundedMask(cornerRadius: CGFloat) {
        guard cornerRadius > 0 else {
            maskImage = nil
            return
        }
        let edge = 2 * cornerRadius + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        maskImage = image
    }
}
