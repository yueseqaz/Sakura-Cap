// 生成默认应用图标（樱花粉渐变 + 白色录制环 + 深樱红圆点）
// 用法: swift Scripts/make_default_icon.swift <输出.png>
import AppKit
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 背景圆角矩形 + 樱花粉对角渐变
let radius: CGFloat = 224
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                   cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let colors = [CGColor(srgbRed: 1.00, green: 0.83, blue: 0.89, alpha: 1),
              CGColor(srgbRed: 0.99, green: 0.55, blue: 0.69, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// 白色录制环
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96))
ctx.setLineWidth(58)
ctx.strokeEllipse(in: CGRect(x: 236, y: 236, width: 552, height: 552))

// 中心录制圆点（深樱红）
ctx.setFillColor(CGColor(srgbRed: 0.90, green: 0.17, blue: 0.32, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 362, y: 362, width: 300, height: 300))

// 右上角花瓣点缀（两片半透明白）
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5))
ctx.fillEllipse(in: CGRect(x: 760, y: 772, width: 96, height: 96))
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.3))
ctx.fillEllipse(in: CGRect(x: 690, y: 858, width: 52, height: 52))

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("写入图标失败\n", stderr)
    exit(1)
}
print("已生成默认图标: \(outPath)")
