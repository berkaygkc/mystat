// Renders an HTML page in WebKit, writes a PNG and reports JS errors.
// Usage: swift tools/mocksnap.swift <html-file|url> <out.png> <width> <height> [js-to-run-first]
import AppKit
import WebKit

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : ""
let resolved = target.hasPrefix("/") || FileManager.default.fileExists(atPath: target) ? URL(fileURLWithPath: target).absoluteString : target
guard args.count >= 5, let url = URL(string: resolved) else {
    print("usage: snap <url> <out.png> <w> <h> [js]"); exit(2)
}
let out = args[2]
let w = CGFloat(Double(args[3]) ?? 1400), h = CGFloat(Double(args[4]) ?? 1000)
let noTransitions = "(()=>{const st=document.createElement('style');st.textContent='*{transition:none!important;animation:none!important}';document.head.appendChild(st);})();"
let preJS = noTransitions + (args.count > 5 ? args[5] : "1")

final class Delegate: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var errors: [String] = []
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        errors.append("\(m.body)")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            webView.evaluateJavaScript(preJS.isEmpty ? "1" : preJS) { res, err in
                if let err { self.errors.append("preJS: \(err)") }
                if let res { print("preJS result: \(res)") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let cfg = WKSnapshotConfiguration()
                    webView.takeSnapshot(with: cfg) { img, err in
                        if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: out))
                            print("saved \(out)")
                        } else { print("snapshot failed: \(String(describing: err))") }
                        print(self.errors.isEmpty ? "JS errors: none" : "JS errors:\n" + self.errors.joined(separator: "\n"))
                        exit(0)
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let d = Delegate()
let ucc = WKUserContentController()
ucc.add(d, name: "err")
let hook = """
window.addEventListener('error', e => window.webkit.messageHandlers.err.postMessage((e.message||'') + ' @' + (e.lineno||'?')));
window.addEventListener('unhandledrejection', e => window.webkit.messageHandlers.err.postMessage('rejection: ' + e.reason));
"""
ucc.addUserScript(WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
let conf = WKWebViewConfiguration()
conf.userContentController = ucc
let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h), configuration: conf)
let win = NSWindow(contentRect: wv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = wv
wv.navigationDelegate = d
if url.isFileURL { wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) } else { wv.load(URLRequest(url: url)) }
DispatchQueue.main.asyncAfter(deadline: .now() + 25) { print("timeout; errors: \(d.errors)"); exit(1) }
app.run()
