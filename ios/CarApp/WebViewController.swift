import UIKit
import WebKit
import CoreLocation

final class WebViewController: UIViewController,
                               WKNavigationDelegate,
                               WKUIDelegate,
                               WKScriptMessageHandler,
                               CLLocationManagerDelegate {

    private var webView: WKWebView!
    private var refreshControl: UIRefreshControl!
    private let locManager = CLLocationManager()

    /// 服务器地址：优先读 Info.plist 的 ServerURL，可在 Xcode 里直接改
    private var serverURL: URL {
        if let s = Bundle.main.object(forInfoDictionaryKey: "ServerURL") as? String,
           let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return u
        }
        return URL(string: "http://192.168.123.72:8088")!
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 243/255, green: 246/255, blue: 250/255, alpha: 1)

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        // 允许页面用 localStorage 持久化
        cfg.websiteDataStore = .default()

        let ucc = WKUserContentController()
        ucc.add(self, name: "native")
        cfg.userContentController = ucc

        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(onRefresh), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)

        locManager.delegate = self
        locManager.requestWhenInUseAuthorization()

        load()
    }

    private func load() {
        // 带上时间戳避免缓存旧页面
        var comps = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))"))
        comps?.queryItems = items
        let target = comps?.url ?? serverURL
        var req = URLRequest(url: target)
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(req)
    }

    @objc private func onRefresh() {
        webView.reload()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        // 高德 / 电话 / 邮件 / 外链交给系统
        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "file", "about"].contains(scheme) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            decisionHandler(.cancel)
            return
        }
        // 非本机域名的 http(s) 用 Safari 打开（导航、支付等）
        if let host = url.host, let selfHost = serverURL.host, host != selfHost {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(a.textFields?.first?.text)
        })
        present(a, animated: true)
    }

    /// iOS 15+ 摄像头/麦克风授权透传
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        // 预留：页面可通过 window.webkit.messageHandlers.native.postMessage("refresh") 触发刷新
        if let cmd = message.body as? String, cmd == "refresh" {
            webView.reload()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 授权变化后无需额外处理，WebView 自行读取
    }
}
