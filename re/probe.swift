// Probe for the fifine D6 (MiraBox protocol). Usage:
//   swift probe.swift list
//   swift probe.swift listen <usage> <secs>
//   swift probe.swift send <usage> <packet> [<packet>...]   packet: "CRT..LIG..#64" style, see parse()
//   swift probe.swift image <key> <file.jpg>
import Foundation
import IOKit.hid

let vid = 0x3142, pid = 0x0007

func devices() -> [IOHIDDevice] {
    let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: vid, kIOHIDProductIDKey: pid] as CFDictionary)
    return (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>).map(Array.init) ?? []
}
func prop(_ d: IOHIDDevice, _ k: String) -> Int { (IOHIDDeviceGetProperty(d, k as CFString) as? Int) ?? -1 }
func dev(usage: Int) -> IOHIDDevice {
    guard let d = devices().first(where: { prop($0, kIOHIDPrimaryUsageKey) == usage }) else { fatalError("no iface usage \(usage)") }
    let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
    guard r == kIOReturnSuccess else { fatalError("open failed 0x\(String(r, radix: 16)) (is the official app running?)") }
    return d
}
func hex(_ b: some Sequence<UInt8>) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

// "CRT..LIG..#64" -> '.' is 0x00, '#hh' is a hex byte, other chars literal ASCII. "x:0a0b" is raw hex.
func parse(_ s: String) -> [UInt8] {
    if s.hasPrefix("x:") {
        let h = Array(s.dropFirst(2)); return stride(from: 0, to: h.count, by: 2).map { UInt8(String(h[$0...$0+1]), radix: 16)! }
    }
    var out: [UInt8] = []; var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if c == "." { out.append(0) }
        else if c == "#" { let j = s.index(i, offsetBy: 2); out.append(UInt8(s[s.index(after: i)...j], radix: 16)!); i = j }
        else { out.append(UInt8(c.asciiValue!)) }
        i = s.index(after: i)
    }
    return out
}
func write(_ d: IOHIDDevice, _ bytes: [UInt8]) {
    let size = prop(d, kIOHIDMaxOutputReportSizeKey)
    var buf = bytes + [UInt8](repeating: 0, count: max(0, size - bytes.count))
    let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0, &buf, buf.count)
    print("-> [\(buf.count)] \(hex(bytes.prefix(24)))  ret=0x\(String(r, radix: 16))")
}
func listen(_ d: IOHIDDevice, secs: Double) {
    let size = prop(d, kIOHIDMaxInputReportSizeKey)
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    IOHIDDeviceRegisterInputReportCallback(d, buf, size, { _, _, _, _, _, report, len in
        print("<- [\(len)] \(hex(UnsafeBufferPointer(start: report, count: min(len, 24))))")
    }, nil)
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    RunLoop.current.run(until: Date().addingTimeInterval(secs))
}

let a = CommandLine.arguments
switch a.count > 1 ? a[1] : "list" {
case "list":
    for d in devices() {
        print(["PrimaryUsagePage", "PrimaryUsage", "MaxInputReportSize", "MaxOutputReportSize", "MaxFeatureReportSize"].map { "\($0)=\(prop(d, $0))" }.joined(separator: " "))
    }
case "listen":
    listen(dev(usage: Int(a[2])!), secs: Double(a[3])!)
case "send":
    let d = dev(usage: Int(a[2])!)
    for p in a.dropFirst(3) { write(d, parse(p)); usleep(50_000) }
    listen(d, secs: 0.5)
case "image":
    let d = dev(usage: 1), key = UInt8(a[2])!, jpg = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: a[3])))
    let n = jpg.count
    write(d, parse("CRT..BAT") + [UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff), key])
    let chunk = prop(d, kIOHIDMaxOutputReportSizeKey)
    for off in stride(from: 0, to: n, by: chunk) { write(d, Array(jpg[off..<min(off + chunk, n)])) }
    write(d, parse("CRT..STP"))
    listen(d, secs: 0.5)
case "numbers": // numbers <size>: draw each key's index on it
    let d = dev(usage: 1), size = Int(a[2])!
    write(d, parse("CRT..DIS")); write(d, parse("CRT..LIG..#64")); write(d, parse("CRT..CLE...#ff"))
    for key in 1...15 {
        let jpg = label("\(key)", size: size)
        write(d, parse("CRT..BAT") + [UInt8(jpg.count >> 24 & 0xff), UInt8(jpg.count >> 16 & 0xff), UInt8(jpg.count >> 8 & 0xff), UInt8(jpg.count & 0xff), UInt8(key)])
        for off in stride(from: 0, to: jpg.count, by: 512) { write(d, Array(jpg[off..<min(off + 512, jpg.count)])) }
    }
    write(d, parse("CRT..STP"))
    listen(d, secs: 0.5)
case "rgb": // rgb <prefix: none|CRT|CRT..> <r> <g> <b>
    let d = dev(usage: 1), rgb = [UInt8(a[3])!, UInt8(a[4])!, UInt8(a[5])!]
    let body = [65, 100, 18] + Array((0..<18).map { _ in rgb }.joined())
    write(d, (a[2] == "none" ? [] : parse(a[2])) + body)
    listen(d, secs: 0.5)
default: print("unknown")
}

import AppKit
func label(_ text: String, size: Int) -> [UInt8] {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        NSColor(calibratedHue: CGFloat(Int(text)! * 23 % 100) / 100, saturation: 0.7, brightness: 0.6, alpha: 1).setFill(); r.fill()
        NSColor.white.setFill(); NSRect(x: 0, y: r.height - 8, width: 8, height: 8).fill() // top-left marker shows rotation
        let s = text as NSString, attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: CGFloat(size) / 2), .foregroundColor: NSColor.white]
        let ctx = NSGraphicsContext.current!.cgContext // device panels are mounted upside down
        ctx.translateBy(x: r.width, y: r.height); ctx.rotate(by: .pi)
        NSColor.white.setFill(); NSRect(x: 0, y: r.height - 8, width: 8, height: 8).fill()
        let sz = s.size(withAttributes: attrs); s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2), withAttributes: attrs)
        return true
    }
    let rep = NSBitmapImageRep(cgImage: img.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    return [UInt8](rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!)
}
