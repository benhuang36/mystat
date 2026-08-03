import SwiftUI

extension NSVisualEffectView {
    /// Mask the material to a rounded rectangle. `cornerRadius <= 0` clears it.
    ///
    /// A behind-window material ignores `layer.cornerRadius`/`masksToBounds`, so
    /// the corners must be clipped with a resizable `maskImage`; without this the
    /// square material corners bleed out behind the rounded window.
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
