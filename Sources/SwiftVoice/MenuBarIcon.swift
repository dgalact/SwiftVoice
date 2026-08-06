import AppKit

enum MenuBarIcon {
    static func make(isRecording: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let head = NSBezierPath(
            roundedRect: NSRect(x: 2.5, y: 3, width: 13, height: 10.5),
            xRadius: 3,
            yRadius: 3
        )
        head.lineWidth = 1.6
        head.stroke()

        let leftAntenna = NSBezierPath()
        leftAntenna.move(to: NSPoint(x: 6, y: 13))
        leftAntenna.line(to: NSPoint(x: 4.5, y: 16))
        leftAntenna.lineWidth = 1.4
        leftAntenna.lineCapStyle = .round
        leftAntenna.stroke()

        let rightAntenna = NSBezierPath()
        rightAntenna.move(to: NSPoint(x: 12, y: 13))
        rightAntenna.line(to: NSPoint(x: 13.5, y: 16))
        rightAntenna.lineWidth = 1.4
        rightAntenna.lineCapStyle = .round
        rightAntenna.stroke()

        NSBezierPath(ovalIn: NSRect(x: 5.2, y: 8.3, width: 2, height: 2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.8, y: 8.3, width: 2, height: 2)).fill()

        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: 6.5, y: 6))
        mouth.curve(
            to: NSPoint(x: 11.5, y: 6),
            controlPoint1: NSPoint(x: 7.7, y: isRecording ? 4.7 : 5.2),
            controlPoint2: NSPoint(x: 10.3, y: isRecording ? 4.7 : 5.2)
        )
        mouth.lineWidth = isRecording ? 2 : 1.3
        mouth.lineCapStyle = .round
        mouth.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
