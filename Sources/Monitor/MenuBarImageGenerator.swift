import Cocoa

struct MenuBarImageGenerator {
    
    /// Generates a simple history line chart
    static func generateHistoryChart(history: [Double], color: NSColor, secondaryHistory: [Double]? = nil, secondaryColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 32, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let hasSecondary = secondaryHistory != nil && secondaryColor != nil
            
            // Draw background box (inset by 0.5 for pixel-perfect sharpness)
            let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            bgPath.lineWidth = 1
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
            bgPath.stroke()
            
            if hasSecondary {
                let sepPath = NSBezierPath()
                sepPath.move(to: NSPoint(x: 0, y: 8.5))
                sepPath.line(to: NSPoint(x: 32, y: 8.5))
                NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
                sepPath.lineWidth = 1
                sepPath.stroke()
            }
            
            // Helper function to draw a line
            func drawLine(data: [Double], c: NSColor, drawRect: NSRect, mirrored: Bool) {
                if data.count > 1 {
                    let maxVal = max(100.0, data.max() ?? 100.0)
                    let stepX = drawRect.width / CGFloat(data.count - 1)
                    
                    let linePath = NSBezierPath()
                    let fillPath = NSBezierPath()
                    
                    let baseLineY = mirrored ? drawRect.maxY : drawRect.minY
                    
                    for (i, val) in data.enumerated() {
                        let x = drawRect.minX + CGFloat(i) * stepX
                        
                        let yOffset = CGFloat((val / maxVal)) * drawRect.height
                        let y = mirrored ? drawRect.maxY - yOffset : drawRect.minY + yOffset
                        
                        let point = NSPoint(x: x, y: y)
                        
                        if i == 0 {
                            linePath.move(to: point)
                            fillPath.move(to: NSPoint(x: x, y: baseLineY))
                            fillPath.line(to: point)
                        } else {
                            linePath.line(to: point)
                            fillPath.line(to: point)
                        }
                    }
                    
                    fillPath.line(to: NSPoint(x: drawRect.maxX, y: baseLineY))
                    fillPath.close()
                    
                    c.withAlphaComponent(0.3).setFill()
                    fillPath.fill()
                    
                    c.setStroke()
                    linePath.lineWidth = 1.0
                    linePath.stroke()
                }
            }
            
            if hasSecondary, let secHist = secondaryHistory, let secColor = secondaryColor {
                // Top half (Primary/Download), growing upwards
                drawLine(data: history, c: color, drawRect: NSRect(x: 0, y: 8, width: 32, height: 8), mirrored: false)
                // Bottom half (Secondary/Upload), growing downwards from the center line
                drawLine(data: secHist, c: secColor, drawRect: NSRect(x: 0, y: 0, width: 32, height: 8), mirrored: true)
            } else {
                drawLine(data: history, c: color, drawRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), mirrored: false)
            }
            
            return true
        }
        return image
    }
    
    /// Generates a circular pie chart
    static func generatePieChart(value: Double, color: NSColor, secondaryValue: Double? = nil, secondaryColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = size.width / 2.0
            
            // Background circle
            NSColor.controlTextColor.withAlphaComponent(0.3).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            
            // Primary Pie slice (Clockwise from top)
            let angle = CGFloat((value / 100.0) * 360.0)
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - angle, clockwise: true)
            path.close()
            color.setFill()
            path.fill()
            
            // Secondary Pie slice (Counter-Clockwise from top)
            if let secVal = secondaryValue, let secColor = secondaryColor {
                let secAngle = CGFloat((secVal / 100.0) * 360.0)
                let secPath = NSBezierPath()
                secPath.move(to: center)
                secPath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 + secAngle, clockwise: false)
                secPath.close()
                secColor.setFill()
                secPath.fill()
            }
            
            return true
        }
        return image
    }
    
    /// Generates an arc/gauge chart
    static func generateGauge(value: Double, color: NSColor, secondaryValue: Double? = nil, secondaryColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let drawRect = NSRect(x: 2, y: 2, width: 12, height: 12)
            let center = NSPoint(x: size.width / 2, y: size.height / 2)
            
            let hasSecondary = secondaryValue != nil
            
            // Outer radius for primary, inner for secondary
            let outerRadius = drawRect.width / 2.0
            let innerRadius = outerRadius - 2.5
            
            // Background track (outer)
            let trackPath = NSBezierPath()
            trackPath.appendArc(withCenter: center, radius: outerRadius, startAngle: 0, endAngle: 360)
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
            trackPath.lineWidth = hasSecondary ? 2 : 3
            trackPath.stroke()
            
            // Background track (inner)
            if hasSecondary {
                let innerTrackPath = NSBezierPath()
                innerTrackPath.appendArc(withCenter: center, radius: innerRadius, startAngle: 0, endAngle: 360)
                NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
                innerTrackPath.lineWidth = 2
                innerTrackPath.stroke()
            }
            
            // Value track (outer)
            if value > 0 {
                let angle = CGFloat((value / 100.0) * 360.0)
                let valPath = NSBezierPath()
                valPath.appendArc(withCenter: center, radius: outerRadius, startAngle: 90, endAngle: 90 - angle, clockwise: true)
                color.setStroke()
                valPath.lineWidth = hasSecondary ? 2 : 3
                valPath.lineCapStyle = .round
                valPath.stroke()
            }
            
            // Value track (inner)
            if let secVal = secondaryValue, let secColor = secondaryColor, secVal > 0 {
                let angle = CGFloat((secVal / 100.0) * 360.0)
                let valPath = NSBezierPath()
                valPath.appendArc(withCenter: center, radius: innerRadius, startAngle: 90, endAngle: 90 - angle, clockwise: true)
                secColor.setStroke()
                valPath.lineWidth = 2
                valPath.lineCapStyle = .round
                valPath.stroke()
            }
            
            return true
        }
        return image
    }
    
    /// Generates vertical bar chart (cores style)
    static func generateBarChart(value: Double, color: NSColor, secondaryValue: Double? = nil, secondaryColor: NSColor? = nil) -> NSImage {
        let hasSecondary = secondaryValue != nil
        let size = hasSecondary ? NSSize(width: 21, height: 18) : NSSize(width: 11, height: 18)
        
        let image = NSImage(size: size, flipped: false) { rect in
            if hasSecondary {
                let gap: CGFloat = 2.0
                let barWidth: CGFloat = 9.0
                let xOffset: CGFloat = 1.0
                
                // Background boxes (inset by 0.5 for crispness)
                let bgRect1 = NSRect(x: xOffset, y: 0, width: barWidth, height: size.height).insetBy(dx: 0.5, dy: 0.5)
                let bgPath1 = NSBezierPath(roundedRect: bgRect1, xRadius: 2, yRadius: 2)
                NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
                bgPath1.lineWidth = 1
                bgPath1.stroke()
                
                let bgRect2 = NSRect(x: xOffset + barWidth + gap, y: 0, width: barWidth, height: size.height).insetBy(dx: 0.5, dy: 0.5)
                let bgPath2 = NSBezierPath(roundedRect: bgRect2, xRadius: 2, yRadius: 2)
                NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
                bgPath2.lineWidth = 1
                bgPath2.stroke()
                
                // Primary (Left Bar)
                let fillHeight1 = CGFloat((value / 100.0)) * size.height
                if fillHeight1 > 0 {
                    let fillRect1 = NSRect(x: xOffset, y: 0, width: barWidth, height: fillHeight1)
                    let fPath1 = NSBezierPath(roundedRect: fillRect1, xRadius: 2, yRadius: 2)
                    color.setFill()
                    fPath1.fill()
                }
                
                // Secondary (Right Bar)
                if let secVal = secondaryValue, let secColor = secondaryColor {
                    let fillHeight2 = CGFloat((secVal / 100.0)) * size.height
                    if fillHeight2 > 0 {
                        let fillRect2 = NSRect(x: xOffset + barWidth + gap, y: 0, width: barWidth, height: fillHeight2)
                        let fPath2 = NSBezierPath(roundedRect: fillRect2, xRadius: 2, yRadius: 2)
                        secColor.setFill()
                        fPath2.fill()
                    }
                }
            } else {
                // Single Bar
                let barWidth: CGFloat = 9.0
                let xOffset: CGFloat = 2.0
                
                let bgRect = NSRect(x: xOffset, y: 0, width: barWidth, height: size.height).insetBy(dx: 0.5, dy: 0.5)
                let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 2, yRadius: 2)
                NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
                bgPath.lineWidth = 1
                bgPath.stroke()
                
                let fillHeight = CGFloat((value / 100.0)) * size.height
                if fillHeight > 0 {
                    let fillRect = NSRect(x: xOffset, y: 0, width: barWidth, height: fillHeight)
                    let fPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
                    color.setFill()
                    fPath.fill()
                }
            }
            
            return true
        }
        return image
    }
    
    /// Generates one tiny vertical bar per CPU core (iStat-style "Core Bars")
    static func generateCoreBars(usages: [Double], color: NSColor) -> NSImage {
        let cores = usages.isEmpty ? [0.0] : Array(usages.prefix(16))
        let barWidth: CGFloat = 3.0
        let gap: CGFloat = 1.0
        let height: CGFloat = 16.0
        let width = CGFloat(cores.count) * barWidth + CGFloat(cores.count - 1) * gap
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            for (i, usage) in cores.enumerated() {
                let x = CGFloat(i) * (barWidth + gap)

                // Background track
                let trackRect = NSRect(x: x, y: 0, width: barWidth, height: height)
                NSColor.controlTextColor.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: trackRect, xRadius: 1, yRadius: 1).fill()

                // Fill (minimum 1pt so idle cores stay visible)
                let fillHeight = max(1.0, CGFloat(usage / 100.0) * height)
                let fillRect = NSRect(x: x, y: 0, width: barWidth, height: fillHeight)
                color.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        return image
    }

    /// Generates a horizontal capacity bar. With `showNub` it takes a battery shape.
    static func generateCapacityBar(value: Double, color: NSColor, showNub: Bool = false) -> NSImage {
        let bodyWidth: CGFloat = 24.0
        let nubWidth: CGFloat = showNub ? 2.0 : 0.0
        let height: CGFloat = 11.0
        let size = NSSize(width: bodyWidth + nubWidth + (showNub ? 1.0 : 0.0), height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            let bodyRect = NSRect(x: 0, y: 0, width: bodyWidth, height: height)

            // Outline
            let outline = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            NSColor.controlTextColor.withAlphaComponent(0.6).setStroke()
            outline.stroke()

            // Battery nub
            if showNub {
                let nubRect = NSRect(x: bodyWidth + 1.0, y: height / 2 - 2, width: nubWidth, height: 4)
                NSColor.controlTextColor.withAlphaComponent(0.6).setFill()
                NSBezierPath(roundedRect: nubRect, xRadius: 1, yRadius: 1).fill()
            }

            // Fill level
            let inset: CGFloat = 2.0
            let maxFillWidth = bodyRect.width - inset * 2
            let fillWidth = max(0, min(maxFillWidth, CGFloat(value / 100.0) * maxFillWidth))
            if fillWidth > 0.5 {
                let fillRect = NSRect(x: inset, y: inset, width: fillWidth, height: bodyRect.height - inset * 2)
                color.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        return image
    }

    /// Appends a single-line value text (e.g. "42%") to the right of an image
    static func addValueText(_ text: String, to image: NSImage) -> NSImage {
        let spacing: CGFloat = 3

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlTextColor
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()

        // Reserve a stable width to prevent horizontal jitter
        let minTextWidth: CGFloat = 30.0
        let actualTextWidth = max(textSize.width, minTextWidth)

        let totalHeight = max(image.size.height, textSize.height)
        let newSize = NSSize(width: image.size.width + spacing + actualTextWidth, height: totalHeight)

        let newImage = NSImage(size: newSize, flipped: false) { _ in
            let context = NSGraphicsContext.current?.cgContext
            context?.saveGState()
            context?.setShouldAntialias(true)
            context?.setShouldSmoothFonts(true)

            let imgY = (totalHeight - image.size.height) / 2
            image.draw(in: NSRect(x: 0, y: imgY, width: image.size.width, height: image.size.height))

            let textY = (totalHeight - textSize.height) / 2
            attrString.draw(in: NSRect(x: image.size.width + spacing, y: textY, width: actualTextWidth, height: textSize.height))

            context?.restoreGState()
            return true
        }

        newImage.isTemplate = image.isTemplate
        return newImage
    }

    /// Wraps an image with a vertical label (e.g. C\nP\nU) on its left side
    static func addLabel(_ label: String, to image: NSImage) -> NSImage {
        let labelWidth: CGFloat = 7
        let spacing: CGFloat = 3.5
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.maximumLineHeight = 7.0
        paragraphStyle.minimumLineHeight = 7.0
        
        // Increase font size to 7.0 for readability
        let font = NSFont.systemFont(ofSize: 7.0, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.controlTextColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let verticalText = label.contains("\n") ? label : label.map { String($0) }.joined(separator: "\n")
        let attrString = NSAttributedString(string: verticalText, attributes: attributes)
        
        let textSize = attrString.size()
        let totalHeight = max(image.size.height, textSize.height)
        let newSize = NSSize(width: labelWidth + spacing + image.size.width, height: totalHeight)
        
        let newImage = NSImage(size: newSize, flipped: false) { rect in
            let context = NSGraphicsContext.current?.cgContext
            
            // Re-enable antialiasing for both image and text for legibility
            context?.saveGState()
            context?.setShouldAntialias(true)
            context?.setShouldSmoothFonts(true)
            
            let imgY = (totalHeight - image.size.height) / 2
            image.draw(in: NSRect(x: labelWidth + spacing, y: imgY, width: image.size.width, height: image.size.height))
            
            let textY = (totalHeight - textSize.height) / 2
            attrString.draw(in: NSRect(x: 0, y: textY, width: labelWidth, height: textSize.height))
            
            context?.restoreGState()
            return true
        }
        
        newImage.isTemplate = image.isTemplate
        return newImage
    }
    
    static func addSpeedText(_ text: String, to image: NSImage) -> NSImage {
        let spacing: CGFloat = 4
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        // Force the line height to 9.5 so two lines fit perfectly within ~19pt
        paragraphStyle.maximumLineHeight = 9.5
        paragraphStyle.minimumLineHeight = 9.5
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
            .foregroundColor: NSColor.controlTextColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()
        
        // Ensure minimum width to prevent jumping
        let minTextWidth: CGFloat = 45.0
        let actualTextWidth = max(textSize.width, minTextWidth)
        
        // Menu bar height is exactly 22.0. Let's use 22.0 to avoid any internal clipping
        let totalHeight: CGFloat = 22.0
        let newSize = NSSize(width: image.size.width + spacing + actualTextWidth, height: totalHeight)
        
        let newImage = NSImage(size: newSize, flipped: false) { rect in
            let context = NSGraphicsContext.current?.cgContext
            
            context?.saveGState()
            context?.setShouldAntialias(true)
            context?.setShouldSmoothFonts(true)
            
            // Draw image on the left, vertically centered
            let imgY = (totalHeight - image.size.height) / 2.0
            image.draw(in: NSRect(x: 0, y: imgY, width: image.size.width, height: image.size.height))
            
            // Draw text on the right, vertically centered, right-aligned within actualTextWidth
            let textY = ((totalHeight - textSize.height) / 2.0) - 1.0
            attrString.draw(in: NSRect(x: image.size.width + spacing, y: textY, width: actualTextWidth, height: textSize.height))
            
            context?.restoreGState()
            return true
        }
        
        newImage.isTemplate = image.isTemplate
        return newImage
    }
}
