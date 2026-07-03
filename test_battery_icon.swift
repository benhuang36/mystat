import AppKit
if #available(macOS 12.0, *) {
    let img = NSImage(systemSymbolName: "battery.100", variableValue: 0.82, accessibilityDescription: nil)
    print(img != nil ? "Success" : "Failed")
} else {
    print("Not available")
}
