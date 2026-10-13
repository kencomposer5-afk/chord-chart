// tools/vision-ocr.swift
// Reads the text in a chart image with macOS's built-in text recognition (Vision) and prints JSON
// (text + position of every word) that the chord-chart web app can load ("Mac認識結果(JSON)").
//
// Usage (Terminal, macOS 13+):
//   swift vision-ocr.swift 1.png > 1.json
//   swift vision-ocr.swift 2.png 3 > 2.json      # optional 2nd argument: upscale factor (default 3)
import Foundation
import Vision
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: swift vision-ocr.swift image.png [scale]\n", stderr)
    exit(1)
}
let scale = args.count >= 3 ? max(1, Int(args[2]) ?? 3) : 3

guard let nsImage = NSImage(contentsOf: URL(fileURLWithPath: args[1])),
      let source = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("cannot read image: \(args[1])\n", stderr)
    exit(1)
}
let W = source.width, H = source.height

// white background + upscaling helps with the thin, small chord glyphs
let bw = W * scale, bh = H * scale
guard let ctx = CGContext(data: nil, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("cannot create context\n", stderr)
    exit(1)
}
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: bw, height: bh))
ctx.interpolationQuality = .high
ctx.draw(source, in: CGRect(x: 0, y: 0, width: bw, height: bh))
guard let big = ctx.makeImage() else { exit(1) }

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages = ["en-US"]
request.minimumTextHeight = 0

do {
    try VNImageRequestHandler(cgImage: big, options: [:]).perform([request])
} catch {
    fputs("recognition failed: \(error)\n", stderr)
    exit(1)
}

var items: [[String: Any]] = []
for obs in request.results ?? [] {
    guard let cand = obs.topCandidates(1).first else { continue }
    let s = cand.string
    var i = s.startIndex
    while i < s.endIndex {
        while i < s.endIndex && s[i].isWhitespace { i = s.index(after: i) }
        if i >= s.endIndex { break }
        var j = i
        while j < s.endIndex && !s[j].isWhitespace { j = s.index(after: j) }
        let word = String(s[i..<j])
        // Vision boxes are normalised, origin at the bottom-left
        let box = (try? cand.boundingBox(for: i..<j))?.boundingBox ?? obs.boundingBox
        items.append([
            "t": word,
            "x": Double(box.minX) * Double(W),
            "y": (1.0 - Double(box.maxY)) * Double(H),
            "w": Double(box.width) * Double(W),
            "h": Double(box.height) * Double(H),
            "c": Double(cand.confidence),
        ])
        i = j
    }
}

let out: [String: Any] = ["width": W, "height": H, "items": items]
let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted])
FileHandle.standardOutput.write(data)
