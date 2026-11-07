#!/usr/bin/env swift
import AppKit

let output=CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,bitsPerSample:8,
                                samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
      let context=NSGraphicsContext(bitmapImageRep:bitmap),
      let book=NSImage(contentsOfFile:"Resources/Assets.xcassets/BrandBook.imageset/BrandBook.png") else {fatalError("Missing brand artwork")}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=context
context.imageInterpolation = .high
let rect=NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024))
NSGradient(colors:[NSColor(calibratedRed:0.13,green:0.07,blue:0.21,alpha:1),
                   NSColor(calibratedRed:0.035,green:0.025,blue:0.065,alpha:1)])!.draw(in:rect,angle:75)
let width:CGFloat=810
let height=width*book.size.height/book.size.width
book.draw(in:NSRect(x:(1024-width)/2,y:(1024-height)/2,width:width,height:height))
NSGraphicsContext.restoreGraphicsState()
let url=URL(fileURLWithPath:output)
try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
guard let png=bitmap.representation(using:.png,properties:[:]) else {fatalError("Icon encoding failed")}
try png.write(to:url)
print("Icon created: "+url.path)
