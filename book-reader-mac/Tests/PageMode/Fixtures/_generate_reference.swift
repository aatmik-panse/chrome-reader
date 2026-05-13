#!/usr/bin/env swift
import Foundation
import PDFKit
import CoreImage
import AppKit

let fixtureDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let pdfURL = fixtureDir.appendingPathComponent("sample.pdf")
let referenceURL = fixtureDir.appendingPathComponent("pdf-dark-reference.png")

guard let doc = PDFDocument(url: pdfURL), let page = doc.page(at: 0) else {
    fatalError("missing sample.pdf at \(pdfURL.path)")
}
let thumbnailSize = CGSize(width: 612, height: 792) // letter at 1pt = 1px
let thumb: NSImage = page.thumbnail(of: thumbnailSize, for: .mediaBox)

guard let tiff = thumb.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let cg = bitmap.cgImage else { fatalError("bitmap from thumbnail") }
let ciImage = CIImage(cgImage: cg)

let invert = CIFilter(name: "CIColorInvert")!
invert.setValue(ciImage, forKey: kCIInputImageKey)
let inverted = invert.outputImage!

let hue = CIFilter(name: "CIHueAdjust")!
hue.setValue(inverted, forKey: kCIInputImageKey)
hue.setValue(NSNumber(value: Double.pi), forKey: kCIInputAngleKey) // ~180°
let rotated = hue.outputImage!

let context = CIContext()
guard let outCG = context.createCGImage(rotated, from: rotated.extent) else {
    fatalError("createCGImage")
}
let rep = NSBitmapImageRep(cgImage: outCG)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("png encoding")
}
try png.write(to: referenceURL)
print("wrote", referenceURL.path)
