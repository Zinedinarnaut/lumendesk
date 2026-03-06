import AppKit
import SwiftUI
import WebKit

struct WebWallpaperView: NSViewRepresentable {
    let url: URL
    let isPaused: Bool
    let frameRateLimit: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let userContentController = WKUserContentController()
        userContentController.addUserScript(.lumenDeskScript)
        configuration.userContentController = userContentController

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.customUserAgent = "LumenDesk/1.0"
        view.navigationDelegate = context.coordinator

        context.coordinator.load(url: url, in: view)
        context.coordinator.updatePlaybackState(
            isPaused: isPaused,
            frameRateLimit: frameRateLimit,
            in: view
        )

        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(url: url, in: webView)
        context.coordinator.updatePlaybackState(
            isPaused: isPaused,
            frameRateLimit: frameRateLimit,
            in: webView
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var currentURL: URL?
        private var didFailCurrentLoad = false
        private var attemptedLocalFallback = false

        func load(url: URL, in webView: WKWebView) {
            if currentURL != url {
                currentURL = url
                didFailCurrentLoad = false
                attemptedLocalFallback = false
                loadRequest(url: url, in: webView)
                return
            }

            if didFailCurrentLoad {
                didFailCurrentLoad = false
                loadRequest(url: url, in: webView)
            }
        }

        func updatePlaybackState(isPaused: Bool, frameRateLimit: Int, in webView: WKWebView) {
            let fps = max(1, min(frameRateLimit, 120))
            let pausedLiteral = isPaused ? "true" : "false"
            let stateScript = "window.__lumenDeskSetState(\(pausedLiteral), \(fps));"
            webView.evaluateJavaScript(stateScript, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFailCurrentLoad = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(webView: webView, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(webView: webView, error: error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            guard navigationResponse.isForMainFrame else {
                decisionHandler(.allow)
                return
            }

            let mimeType = navigationResponse.response.mimeType?.lowercased() ?? ""
            guard mimeType.hasPrefix("video/"), let videoURL = navigationResponse.response.url else {
                decisionHandler(.allow)
                return
            }

            loadVideoWrapper(for: videoURL, in: webView)
            decisionHandler(.cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        private func handleLoadFailure(webView: WKWebView, error: Error) {
            didFailCurrentLoad = true
            fputs("[LumenDesk] Web wallpaper load failed: \(error.localizedDescription)\n", stderr)

            guard !attemptedLocalFallback,
                  let fallbackURL = localFallbackURL(from: currentURL)
            else {
                return
            }

            attemptedLocalFallback = true
            loadRequest(url: fallbackURL, in: webView)
        }

        private func loadRequest(url: URL, in webView: WKWebView) {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            webView.load(request)
        }

        private func loadVideoWrapper(for videoURL: URL, in webView: WKWebView) {
            let escapedURL = escapeHTMLAttribute(videoURL.absoluteString)
            let html = """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>
                html, body {
                  margin: 0;
                  width: 100%;
                  height: 100%;
                  background: #000;
                  overflow: hidden;
                }
                video {
                  width: 100%;
                  height: 100%;
                  object-fit: cover;
                }
              </style>
            </head>
            <body>
              <video autoplay loop muted playsinline src="\(escapedURL)"></video>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: videoURL.deletingLastPathComponent())
        }

        private func escapeHTMLAttribute(_ value: String) -> String {
            value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        private func localFallbackURL(from url: URL?) -> URL? {
            guard
                let url,
                let host = url.host,
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                return nil
            }

            if host.hasSuffix(".localhost") {
                components.host = "localhost"
                return components.url
            }

            if host == "localhost" {
                components.host = "127.0.0.1"
                return components.url
            }

            return nil
        }
    }
}

private extension WKUserScript {
    static let lumenDeskScript = WKUserScript(
        source: """
        (() => {
          if (window.__lumenDeskInit) { return; }
          window.__lumenDeskInit = true;
          window.__lumenDeskPaused = false;
          window.__lumenDeskFPS = 30;

          const nativeRAF = window.requestAnimationFrame.bind(window);
          const frameState = { lastFrame: 0 };

          window.__lumenDeskFrameLoop = function(callback) {
            return nativeRAF((timestamp) => {
              if (window.__lumenDeskPaused) {
                window.__lumenDeskFrameLoop(callback);
                return;
              }

              const frameDelta = 1000 / Math.max(1, Number(window.__lumenDeskFPS) || 30);
              if (timestamp - frameState.lastFrame >= frameDelta) {
                frameState.lastFrame = timestamp;
                callback(timestamp);
              } else {
                window.__lumenDeskFrameLoop(callback);
              }
            });
          };

          window.requestAnimationFrame = function(callback) {
            return window.__lumenDeskFrameLoop(callback);
          };

          window.__lumenDeskSetState = function(paused, fps) {
            window.__lumenDeskPaused = !!paused;
            window.__lumenDeskFPS = Number(fps) || 30;

            document.documentElement.style.animationPlayState = paused ? 'paused' : 'running';

            const mediaNodes = document.querySelectorAll('video, audio');
            mediaNodes.forEach((node) => {
              if (paused) {
                node.pause();
                return;
              }
              const maybePromise = node.play();
              if (maybePromise && typeof maybePromise.catch === 'function') {
                maybePromise.catch(() => {});
              }
            });
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )
}
