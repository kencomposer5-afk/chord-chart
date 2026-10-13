// ChordChartMac.swift - the chord-chart web app in a Mac window, with Apple's Vision text recognition built in.
//
//   * the web files are served from inside the app on http://127.0.0.1:48731 (so the page keeps its saved data)
//   * the page calls  window.webkit.messageHandlers.vision.postMessage({image: dataURL})  and gets back
//     {width, height, items:[{t,x,y,w,h,c}]}  (text, position in pixels, confidence)
//   * files the page "downloads" (PDF, saved charts) go to your Downloads folder
//
// Build:  bash build.sh   (needs the Xcode command line tools, macOS 13+)

import SwiftUI
import WebKit
import Vision
import Network

// MARK: - tiny local web server

final class LocalServer {
    private var listener: NWListener?
    private let root: URL
    private let port: UInt16

    init(root: URL, port: UInt16) {
        self.root = root.standardized
        self.port = port
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            guard let p = NWEndpoint.Port(rawValue: port) else { return }
            let l = try NWListener(using: params, on: p)
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.start(queue: .global())
            listener = l
        } catch {
            NSLog("server start failed: \(error)")
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let text = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            let first = text.components(separatedBy: "\r\n").first ?? ""
            let parts = first.split(separator: " ")
            var path = parts.count > 1 ? String(parts[1]) : "/"
            if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
            if path == "/" { path = "/index.html" }
            let rel = (path.removingPercentEncoding ?? path).dropFirst()
            let file = self.root.appendingPathComponent(String(rel)).standardized
            guard file.path.hasPrefix(self.root.path), let body = try? Data(contentsOf: file) else {
                let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                return
            }
            let head = "HTTP/1.1 200 OK\r\nContent-Type: \(LocalServer.mime(file.pathExtension))\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            var out = head.data(using: .utf8) ?? Data()
            out.append(body)
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "json": return "application/json"
        case "css": return "text/css; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Vision text recognition

enum VisionOCR {
    static func recognize(_ source: CGImage) throws -> [String: Any] {
        let W = source.width, H = source.height
        let scale = W > 1200 ? 2 : 3                       // thin, small glyphs read better when enlarged
        let bw = W * scale, bh = H * scale
        guard let ctx = CGContext(data: nil, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "ocr", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot create context"])
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: bw, height: bh))
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: bw, height: bh))
        guard let big = ctx.makeImage() else {
            throw NSError(domain: "ocr", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot scale image"])
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: big, options: [:]).perform([request])

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
                let box = (try? cand.boundingBox(for: i..<j))?.boundingBox ?? obs.boundingBox   // normalised, origin bottom-left
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
        return ["width": W, "height": H, "items": items]
    }
}

// MARK: - bridge: page -> Vision -> page

final class VisionBridge: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let dataURL = body["image"] as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]), options: .ignoreUnknownCharacters),
              let nsImage = NSImage(data: data),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            replyHandler(nil, "bad image")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try VisionOCR.recognize(cg)
                DispatchQueue.main.async { replyHandler(result, nil) }
            } catch {
                DispatchQueue.main.async { replyHandler(nil, "\(error)") }
            }
        }
    }
}

// MARK: - web view

struct WebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addScriptMessageHandler(VisionBridge(), contentWorld: .page, name: "vision")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        if #available(macOS 13.3, *) { wv.isInspectable = true }     // Safari > Develop menu can then show the page's console
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { wv.load(URLRequest(url: url)) }   // let the local server come up
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate, WKUIDelegate {
        // <input type="file"> does nothing in a Mac WKWebView unless the app shows the open panel itself
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.begin { result in completionHandler(result == .OK ? panel.urls : nil) }
        }
        // alert() / confirm() are silently ignored unless the app shows them
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = NSAlert()
            a.messageText = message
            a.addButton(withTitle: "OK")
            a.runModal()
            completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = NSAlert()
            a.messageText = message
            a.addButton(withTitle: "OK")
            a.addButton(withTitle: "キャンセル")
            completionHandler(a.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let ns = suggestedFilename as NSString
            var dest = dir.appendingPathComponent(suggestedFilename)
            var n = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                let ext = ns.pathExtension
                dest = dir.appendingPathComponent("\(ns.deletingPathExtension) (\(n))" + (ext.isEmpty ? "" : ".\(ext)"))
                n += 1
            }
            completionHandler(dest)
        }
    }
}

// MARK: - app

@main
struct ChordChartApp: App {
    private let server: LocalServer
    private let port: UInt16 = 48731

    init() {
        let web = (Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")).appendingPathComponent("web")
        server = LocalServer(root: web, port: port)
        server.start()
    }

    var body: some Scene {
        WindowGroup("コード譜リレイアウト") {
            WebView(url: URL(string: "http://127.0.0.1:\(port)/index.html")!)
                .frame(minWidth: 1000, minHeight: 700)
        }
    }
}
