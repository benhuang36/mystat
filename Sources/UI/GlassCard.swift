import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
}

struct CustomDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }
}
