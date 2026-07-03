import AppKit

let symbols = ["battery.0", "battery.25", "battery.50", "battery.75", "battery.100"]
for s in symbols {
    let img = NSImage(systemSymbolName: s, accessibilityDescription: nil)
    print("\(s): \(img != nil)")
}
