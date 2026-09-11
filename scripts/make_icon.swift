// 生成 App 图标（1024x1024 PNG）：渐变圆角方块 + 白色下载箭头
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()

let bg = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: S - 64, height: S - 64),
                      xRadius: 224, yRadius: 224)
NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.44, blue: 0.99, alpha: 1),
                    NSColor(calibratedRed: 0.45, green: 0.22, blue: 0.93, alpha: 1)])!
    .draw(in: bg, angle: -55)

NSColor.white.withAlphaComponent(0.92).setFill()
// 箭头杆
NSBezierPath(roundedRect: NSRect(x: 462, y: 500, width: 100, height: 240),
             xRadius: 24, yRadius: 24).fill()
// 箭头头部
let head = NSBezierPath()
head.move(to: NSPoint(x: 372, y: 548))
head.line(to: NSPoint(x: 652, y: 548))
head.line(to: NSPoint(x: 512, y: 340))
head.close()
head.fill()
// 底部托盘横条
NSColor.white.withAlphaComponent(0.75).setFill()
NSBezierPath(roundedRect: NSRect(x: 316, y: 250, width: 392, height: 62),
             xRadius: 31, yRadius: 31).fill()

img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("已生成 \(out)")
