#!/usr/bin/env swift
import AppKit

let path = CommandLine.arguments.count > 1
  ? CommandLine.arguments[1]
  : "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:1024, pixelsHigh:1024,
    bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false,
    colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not initialize AppKit icon context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSGraphicsContext.current?.imageInterpolation = .high

let background = NSBezierPath(rect: NSRect(x:0, y:0, width:1024, height:1024))
NSGradient(starting: NSColor(calibratedRed:0.19, green:0.12, blue:0.30, alpha:1),
           ending: NSColor(calibratedRed:0.025, green:0.025, blue:0.06, alpha:1))!
    .draw(in:background, angle:60)

let glow = NSBezierPath(ovalIn:NSRect(x:175, y:185, width:675, height:675))
NSGradient(starting: NSColor(calibratedRed:0.50, green:0.23, blue:0.85, alpha:0.6),
           ending: NSColor(calibratedRed:0.24, green:0.13, blue:0.48, alpha:0.03))!
    .draw(in:glow, angle:90)

func page(left: Bool) -> NSBezierPath {
    let p = NSBezierPath()
    if left {
        p.move(to:NSPoint(x:512,y:308))
        p.curve(to:NSPoint(x:232,y:368),
            controlPoint1:NSPoint(x:420,y:344),
            controlPoint2:NSPoint(x:326,y:363))
        p.line(to:NSPoint(x:232,y:750))
        p.curve(to:NSPoint(x:512,y:701),
            controlPoint1:NSPoint(x:325,y:770),
            controlPoint2:NSPoint(x:437,y:736))
    } else {
        p.move(to:NSPoint(x:512,y:308))
        p.curve(to:NSPoint(x:792,y:368),
            controlPoint1:NSPoint(x:604,y:344),
            controlPoint2:NSPoint(x:698,y:363))
        p.line(to:NSPoint(x:792,y:750))
        p.curve(to:NSPoint(x:512,y:701),
            controlPoint1:NSPoint(x:698,y:770),
            controlPoint2:NSPoint(x:587,y:736))
    }
    p.close()
    return p
}
let shadow = NSShadow()
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width:0, height:-5)
shadow.shadowColor = NSColor(calibratedRed:0.51, green:0.21, blue:0.99, alpha:0.8)
shadow.set()

let left = page(left:true)
let right = page(left:false)
NSGradient(starting:NSColor(calibratedRed:0.58,green:0.28,blue:0.97,alpha:1),
           ending:NSColor(calibratedRed:0.14,green:0.065,blue:0.32,alpha:1))!
    .draw(in:left, angle:115)
NSGradient(starting:NSColor(calibratedRed:0.68,green:0.39,blue:0.99,alpha:1),
           ending:NSColor(calibratedRed:0.19,green:0.08,blue:0.40,alpha:1))!
    .draw(in:right, angle:55)

NSShadow().set()
NSColor(calibratedRed:0.80,green:0.65,blue:1,alpha:0.9).setStroke()
left.lineWidth=5
right.lineWidth=5
left.stroke()
right.stroke()
let spine=NSBezierPath()
spine.move(to:NSPoint(x:512,y:308))
spine.line(to:NSPoint(x:512,y:701))
spine.lineWidth=10
spine.stroke()
NSGraphicsContext.restoreGraphicsState()

let url=URL(fileURLWithPath:path)
try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),
    withIntermediateDirectories:true)
guard let png=bitmap.representation(using:.png,properties:[:]) else { fatalError("Cannot encode PNG") }
try png.write(to:url)
print("Icon created: " + url.path)
