#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: check-image-opacity.swift IMAGE...\n".utf8))
    exit(2)
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width > 0,
          image.height > 0 else {
        FileHandle.standardError.write(Data("could not decode image: \(path)\n".utf8))
        exit(1)
    }
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }
        context.setBlendMode(.copy)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return true
    }
    guard rendered else {
        FileHandle.standardError.write(Data("could not rasterize image: \(path)\n".utf8))
        exit(1)
    }
    if stride(from: 3, to: pixels.count, by: 4).contains(where: { pixels[$0] != 255 }) {
        FileHandle.standardError.write(Data("image contains transparent pixels: \(path)\n".utf8))
        exit(1)
    }
}
