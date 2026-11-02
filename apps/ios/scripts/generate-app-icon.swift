#!/usr/bin/env swift
// Restore the original MILO brand asset without redrawing or restyling it.
// swift apps/ios/scripts/generate-app-icon.swift
import Foundation
import ImageIO

let script = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = script.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("docs/operations/agc-assets/app-icon-1024.png")
let target = root.appendingPathComponent("apps/ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      image.width == 1024, image.height == 1024 else {
    fatalError("Original MILO icon must be a valid 1024 × 1024 PNG: \(source.path)")
}
let bytes = try Data(contentsOf: source)
try bytes.write(to: target, options: .atomic)
print("Restored original MILO icon from \(source.lastPathComponent).")
