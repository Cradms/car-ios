import Foundation
import CryptoKit
import UIKit

/// 共享偏好（App Group，小组件也要读）
enum Prefs {
    static let group = "group.com.yg.carapp"

    static var d: UserDefaults {
        UserDefaults(suiteName: group) ?? .standard
    }

    static func s(_ k: String, _ def: String = "") -> String {
        (d.string(forKey: k) ?? def)
    }

    static func set(_ v: String, _ k: String) {
        d.set(v, forKey: k)
    }

    static func i(_ k: String) -> Int { d.integer(forKey: k) }

    static func seti(_ v: Int, _ k: String) { d.set(v, forKey: k) }

    static func b(_ k: String) -> Bool { d.bool(forKey: k) }

    static func setb(_ v: Bool, _ k: String) { d.set(v, forKey: k) }

    static func l(_ k: String) -> Int64 { Int64(d.double(forKey: k)) }

    static func setl(_ v: Int64, _ k: String) { d.set(v, forKey: k) }

    static func remove(_ k: String) { d.removeObject(forKey: k) }
}

/// 长安车联网接口层（按 4.5.6 小组件版 Java 源码复刻）
///
/// 三条通道：
/// 1. m.iov.changan.com.cn —— 短信登录、车况、控车（EasyEADO 同款老通道）
/// 2. open.iov.changan.com.cn —— 扫码登录（OAuth）、车型、VCS-HMAC-SHA256 签名接口
/// 3. incallapi.changan.com.cn —— refresh_token 续期
final class CarAPI {

    static let shared = CarAPI()

    // MARK: - 常量（与 Api.java 一致）

    static let OPEN_HOST = "https://open.iov.changan.com.cn"
    static let MI_HOST = "https://m.iov.changan.com.cn"
    static let CAC_HOST = "https://incallapi.changan.com.cn"

    static let CLIENT_ID = "b235afd313004785bfde580c188c47bb"
    static let CLIENT_SECRET = "YjIzNWFmZDMxMzAwNDc4NQ=="
    static let NONCE = "WYYL"
    static let CAC_CLIENT = "2c918082632162010163388048d60158"
    static let AMAP_KEY = "df41e5f8e37878e1280a6866e44f5347"

    private let UA = "ChanganInCall/5.4.5 (iPhone; iOS 16.0; Scale/3.00)"

    // MARK: - 存储键

    private enum K {
        static let mToken = "m_token"
        static let mRefresh = "m_refresh"
        static let mExpires = "m_expires"
        static let accel = "access_token"     // 开放平台
        static let refresh = "refresh_token"  // 开放平台
        static let secret = "secret_key"
        static let expires = "expires_at"
        static let authCode = "oauth_auth_code"
        static let carId = "carId"
        static let carName = "carName"
        static let series = "c_series"
        static let seriesName = "c_series_name"
        static let vin = "c_vin"
        static let pin = "pin"
        static let phone = "phone"
        static let device = "device_id"
        static let proxyBase = "proxy_base"
    }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 25
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    // MARK: - 会话字段

    /// m.iov 老通道令牌（短信登录得到）
    var token: String {
        get { Prefs.s(K.mToken) }
        set { Prefs.set(newValue, K.mToken) }
    }

    var mRefresh: String {
        get { Prefs.s(K.mRefresh) }
        set { Prefs.set(newValue, K.mRefresh) }
    }

    /// 开放平台令牌（扫码得到）
    var openToken: String {
        get { Prefs.s(K.accel) }
        set { Prefs.set(newValue, K.accel) }
    }

    var openRefresh: String {
        get { Prefs.s(K.refresh) }
        set { Prefs.set(newValue, K.refresh) }
    }

    var secretKey: String {
        get { Prefs.s(K.secret) }
        set { Prefs.set(newValue, K.secret) }
    }

    // 兼容旧 UI 的命名
    var accessToken: String {
        get { token }
        set { token = newValue }
    }

    var refreshToken: String {
        get { mRefresh }
        set { mRefresh = newValue }
    }

    var carId: String {
        get { Prefs.s(K.carId) }
        set { Prefs.set(newValue, K.carId) }
    }

    var carName: String {
        get {
            let n = Prefs.s(K.carName)
            return n.isEmpty ? "我的爱车" : n
        }
        set { Prefs.set(newValue, K.carName) }
    }

    /// 归一化后的车型代码（C211/C236/C281/...）
    var carSeries: String {
        get { Prefs.s(K.series) }
        set { Prefs.set(newValue, K.series) }
    }

    var carSeriesName: String {
        get { Prefs.s(K.seriesName) }
        set { Prefs.set(newValue, K.seriesName) }
    }

    var vin: String {
        get { Prefs.s(K.vin) }
        set { Prefs.set(newValue, K.vin) }
    }

    var phone: String {
        get { Prefs.s(K.phone) }
        set { Prefs.set(newValue, K.phone) }
    }

    var controlPin: String {
        get { Prefs.s(K.pin) }
        set { Prefs.set(newValue, K.pin) }
    }

    var isLoggedIn: Bool { !token.isEmpty && !carId.isEmpty }

    var deviceId: String {
        let cur = Prefs.s(K.device)
        if !cur.isEmpty { return cur }
        let id = UIDevice.current.identifierForVendor?.uuidString
            .replacingOccurrences(of: "-", with: "").lowercased()
            ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        Prefs.set(id, K.device)
        return id
    }

    func logout() {
        [K.mToken, K.mRefresh, K.mExpires, K.accel, K.refresh, K.secret,
         K.expires, K.authCode, K.carId, K.carName, K.series, K.seriesName, K.vin, K.pin]
            .forEach { Prefs.remove($0) }
    }

    // MARK: - 摘要 / 签名

    private func hex(_ d: Digest) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ s: String) -> String {
        hex(SHA256.hash(data: Data(s.utf8)))
    }

    private func hmac256(_ key: String, _ data: String) -> String {
        let k = SymmetricKey(data: Data(key.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: k)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// URLEncoder.encode（空格转 +）
    static func urlEncode(_ v: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let s = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
        return s.replacingOccurrences(of: "%20", with: "+")
    }

    /// k=v&k=v（值做 URL 编码）
    static func kvString(_ map: [String: String]) -> String {
        map.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
    }

    /// 开放平台基础签名：参数升序 + appKey + SHA256 大写
    func signBasic(_ params: [String: String]) -> String {
        var t = params
        t["appKey"] = Self.CLIENT_SECRET
        t.removeValue(forKey: "sign")
        let raw = t.keys.sorted().map { "\($0)=\(t[$0] ?? "")&" }.joined()
        return sha256(raw).uppercased()
    }

    /// 开放业务接口签名 VCS-HMAC-SHA256
    func vcsAuth(method: String, path: String, params: [String: String]?,
                 body: String, secret: String, timestampMs: Int64,
                 headers: [String: String]) -> String {
        var headerStr = ""
        for k in headers.keys.sorted() {
            headerStr += "\(k.lowercased()):\(headers[k] ?? "")\n"
        }
        var canonical = "\(method)\n\(path)"
        if let p = params {
            canonical += "\n" + Self.kvString(p) + "\n"
        } else {
            canonical += "\n\n"
        }
        canonical += headerStr
        canonical += "\n" + sha256(body)
        let hashed = sha256(canonical)
        let toSign = "VCS-HMAC-SHA256\n\(timestampMs)\n\(hashed)"
        return "VCS-HMAC-SHA256 Signature=" + hmac256(secret, toSign)
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: - 网络基础

    private var proxyBase: String { Prefs.s(K.proxyBase) }

    func resolveUrl(_ url: String) -> String {
        let base = proxyBase.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, url.hasPrefix("http") else { return url }
        let comps = URLComponents(string: url)
        let tail = comps?.path ?? ""
        let query = comps?.query.map { "?\($0)" } ?? ""
        if url.contains("open.iov.changan.com.cn") { return base + "/proxy/open" + tail + query }
        if url.contains("m.iov.changan.com.cn") { return base + "/proxy/changan" + tail + query }
        if url.contains("incallapi.changan.com.cn") { return base + "/proxy/cac" + tail + query }
        return url
    }

    func setProxy(_ base: String) {
        var v = base.trimmingCharacters(in: .whitespaces)
        while v.hasSuffix("/") { v.removeLast() }
        if !v.isEmpty && !v.hasPrefix("http") { v = "https://" + v }
        Prefs.set(v, K.proxyBase)
    }

    private func miHeaders() -> [String: String] {
        ["Accept": "application/json, text/plain, */*", "vcs-app-id": "inCall"]
    }

    private func vcsHeaders(ts: Int64) -> [String: String] {
        ["X-VCS-User-Access-Token": token,
         "X-VCS-Timestamp": "\(ts)",
         "X-VCS-Nonce": Self.NONCE]
    }

    /// 原始请求（同步）
    @discardableResult
    func raw(_ urlStr: String, method: String = "GET", form: [String: String]? = nil,
             json: String? = nil, headers: [String: String] = [:], retryHost: Bool = true) -> (Data?, Int) {
        guard let u = URL(string: resolveUrl(urlStr)) else { return (nil, -1) }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.setValue(UA, forHTTPHeaderField: "User-Agent")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let f = form {
            req.httpBody = Self.kvString(f).data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        } else if let j = json {
            req.httpBody = j.data(using: .utf8)
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }

        var out: (Data?, Int) = (nil, -1)
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: req) { d, resp, _ in
            out = (d, (resp as? HTTPURLResponse)?.statusCode ?? -1)
            sem.signal()
        }.resume()
        sem.wait()

        // 代理失败时回落直连
        if out.1 < 200 && retryHost && !proxyBase.isEmpty {
            return self.raw(urlStr, method: method, form: form, json: json,
                            headers: headers, retryHost: false)
        }
        return out
    }

    private func json(_ data: Data?) -> [String: Any]? {
        guard let d = data,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }

    private func bg(_ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    // MARK: - 短信登录

    /// 返回错误文案；nil 表示成功
    func sendCode(_ phone: String) -> String? {
        let (d, _) = raw(Self.MI_HOST + "/api/sms/sendAuthcode", method: "POST",
                         form: ["phone": phone], headers: miHeaders())
        guard let o = json(d) else { return "网络错误" }
        if (o["code"] as? Int) == 0 { return nil }
        return (o["msg"] as? String) ?? "发送失败"
    }

    func sendSms(phone: String, done: @escaping (Bool, String) -> Void) {
        bg {
            let err = self.sendCode(phone)
            DispatchQueue.main.async { done(err == nil, err ?? "验证码已发送") }
        }
    }

    /// 短信登录：mobile + vercode → m.iov token
    func login(phone: String, code: String, pin: String,
               done: @escaping (Bool, String) -> Void) {
        bg {
            var h = self.miHeaders()
            h["X-Requested-With"] = "cn.com.changan.cvim"
            let (d, _) = self.raw(Self.MI_HOST + "/app2/api/oauth2login/token/stageOne",
                                  method: "POST",
                                  form: ["mobile": phone, "vercode": code], headers: h)
            guard let o = self.json(d), (o["code"] as? Int) == 0 else {
                let msg = self.json(d)?["msg"] as? String ?? "验证码错误或已过期"
                DispatchQueue.main.async { done(false, msg) }
                return
            }
            let dd = (o["data"] as? [String: Any]) ?? [:]
            let at = (dd["access_token"] as? String) ?? ""
            guard !at.isEmpty else {
                DispatchQueue.main.async { done(false, "登录失败：未拿到令牌") }
                return
            }
            self.token = at
            if let rt = dd["refresh_token"] as? String, !rt.isEmpty { self.mRefresh = rt }
            let exp = (dd["expires_in"] as? Double) ?? Double(dd["expires_in"] as? Int ?? 0)
            Prefs.setl(Int64(Date().timeIntervalSince1970 * 1000) + Int64(exp * 1000), K.mExpires)
            self.phone = phone
            if !pin.isEmpty { self.controlPin = pin }
            self.loadCars()
            self.legacyRefreshIfNeeded(force: true)
            let name = self.carName
            DispatchQueue.main.async {
                done(self.isLoggedIn, self.isLoggedIn ? "登录成功 · \(name)" : "登录成功，但没取到车辆")
            }
        }
    }

    // MARK: - 扫码登录（开放平台）

    /// 生成二维码：返回 (二维码图片 Data, qrcode_id)
    func qrCreate() -> (Data?, String) {
        var p: [String: String] = [:]
        p["client_id"] = Self.CLIENT_ID
        p["device_id"] = deviceId
        p["nonce"] = Self.NONCE
        p["size"] = "L"
        p["state"] = "OPPOWATCH"
        p["timestamp"] = "\(Int(Date().timeIntervalSince1970))"
        p["sign"] = signBasic(p)
        p["appCode"] = "usercenter"   // appCode 不参与签名

        guard let u = URL(string: Self.OPEN_HOST + "/oauth/api/qrcode/generate") else { return (nil, "") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.kvString(p).data(using: .utf8)

        var imageData: Data?
        var qid = ""
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: req) { d, resp, _ in
            imageData = d
            if let h = resp as? HTTPURLResponse {
                qid = h.value(forHTTPHeaderField: "qrcode_id") ?? ""
            }
            sem.signal()
        }.resume()
        sem.wait()
        return (imageData, qid)
    }

    /// 轮询扫码状态：authorized / scanned / unauthorized / expired
    func qrStatus(_ qrId: String) -> String {
        var p: [String: String] = [:]
        p["timestamp"] = "\(Int(Date().timeIntervalSince1970))"
        p["nonce"] = Self.NONCE
        p["qrcodeId"] = qrId
        p["sign"] = signBasic(p)
        let url = Self.OPEN_HOST + "/oauth/api/qrcode/getQrcodeStatusNoBackend?" + Self.kvString(p)
        let (d, _) = raw(url, headers: ["Accept": "application/json"])
        guard let o = json(d), (o["code"] as? Int) == 0 else { return "unauthorized" }
        var data = o["data"] as? [String: Any]
        if data == nil, let rawStr = o["data"] as? String,
           let dd = rawStr.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: dd) as? [String: Any] {
            data = obj
        }
        guard let dd = data else { return "unauthorized" }
        let result = (dd["result"] as? String) ?? ""
        if result == "authorized" {
            let code = (dd["code"] as? String) ?? ""
            if code.isEmpty { return "unauthorized" }
            Prefs.set(code, K.authCode)
        }
        return result.isEmpty ? "unauthorized" : result
    }

    /// 用扫码授权码换 token；返回错误文案，nil 成功
    func qrExchange() -> String? {
        let code = Prefs.s(K.authCode)
        guard !code.isEmpty else { return "授权码为空，请重新扫码" }
        var p: [String: String] = [:]
        p["client_id"] = Self.CLIENT_ID
        p["client_secret"] = Self.CLIENT_SECRET
        p["grant_type"] = "authorization_code"
        p["redict_uri"] = ""
        p["code"] = code
        let (d, _) = raw(Self.OPEN_HOST + "/oauth/token", method: "POST", form: p)
        guard let o = json(d) else { return "换取令牌失败" }
        let at = (o["access_token"] as? String) ?? ""
        let sk = (o["secret_key"] as? String) ?? ""
        guard !at.isEmpty, !sk.isEmpty else { return "换取令牌失败" }
        openToken = at
        openRefresh = (o["refresh_token"] as? String) ?? ""
        secretKey = sk
        let exp = (o["expires_in"] as? Double) ?? 0
        Prefs.setl(Int64(Date().timeIntervalSince1970 * 1000) + Int64(exp * 1000), K.expires)
        Prefs.remove(K.authCode)
        loadCars()
        return carId.isEmpty ? "已登录，但没取到已绑定车辆" : nil
    }

    // MARK: - 令牌续期

    /// m.iov 老通道续期（incallapi oauth2）
    @discardableResult
    private func legacyRefresh() -> Bool {
        let rt = mRefresh
        guard !rt.isEmpty else { return false }
        let url = Self.CAC_HOST + "/cac/api/v1/oauth2/refresh_token?client_id="
            + Self.CAC_CLIENT + "&refresh_token=" + Self.urlEncode(rt)
        let (d, _) = raw(url, headers: ["Accept": "*/*"])
        guard let o = json(d), (o["status_code"] as? String) == "0" else { return false }
        guard let at = o["access_token"] as? String, !at.isEmpty else { return false }
        token = at
        if let nr = o["refresh_token"] as? String, !nr.isEmpty { mRefresh = nr }
        let exp = (o["expires_in"] as? Double) ?? 0
        Prefs.setl(Int64(Date().timeIntervalSince1970 * 1000) + Int64(exp * 1000), K.mExpires)
        return true
    }

    private func legacyRefreshIfNeeded(force: Bool) {
        let exp = Prefs.l(K.mExpires)
        let due = force || (exp > 0 && nowMs() > exp - 120_000)
        if due { _ = legacyRefresh() }
        openRefreshIfNeeded()
    }

    /// 开放平台续期
    private func openRefreshIfNeeded() {
        let rt = openRefresh
        guard !rt.isEmpty else { return }
        let exp = Prefs.l(K.expires)
        guard exp == 0 || nowMs() > exp - 120_000 else { return }
        var p: [String: String] = [:]
        p["client_id"] = Self.CLIENT_ID
        p["client_secret"] = Self.CLIENT_SECRET
        p["grant_type"] = "refresh_token"
        p["redict_uri"] = ""
        p["refresh_token"] = rt
        let (d, _) = raw(Self.OPEN_HOST + "/oauth/token", method: "POST", form: p)
        guard let o = json(d), let at = o["access_token"] as? String, !at.isEmpty else { return }
        openToken = at
        if let nr = o["refresh_token"] as? String, !nr.isEmpty { openRefresh = nr }
        if let sk = o["secret_key"] as? String, !sk.isEmpty { secretKey = sk }
        let expIn = (o["expires_in"] as? Double) ?? 0
        Prefs.setl(Int64(Date().timeIntervalSince1970 * 1000) + Int64(expIn * 1000), K.expires)
    }

    @discardableResult
    func forceRefresh() -> Bool {
        if legacyRefresh() { return true }
        let rt = openRefresh
        guard !rt.isEmpty else { return false }
        var p: [String: String] = [:]
        p["client_id"] = Self.CLIENT_ID
        p["client_secret"] = Self.CLIENT_SECRET
        p["grant_type"] = "refresh_token"
        p["redict_uri"] = ""
        p["refresh_token"] = rt
        let (d, _) = raw(Self.OPEN_HOST + "/oauth/token", method: "POST", form: p)
        guard let o = json(d), let at = o["access_token"] as? String, !at.isEmpty else { return false }
        openToken = at
        if let nr = o["refresh_token"] as? String, !nr.isEmpty { openRefresh = nr }
        if let sk = o["secret_key"] as? String, !sk.isEmpty { secretKey = sk }
        return true
    }

    func refreshIfNeeded(done: @escaping (Bool) -> Void) {
        bg { done(true) }
    }

    func refresh(done: @escaping (Bool) -> Void) {
        bg {
            let ok = self.forceRefresh()
            DispatchQueue.main.async { done(ok) }
        }
    }

    // MARK: - 车辆列表 / 车型

    /// 绑定车列表 → 按 vin 优先匹配当前车
    func loadCars() {
        legacyRefreshIfNeeded(force: false)
        let url = Self.MI_HOST + "/app2/api/user/cars?type=0&token=" + Self.urlEncode(token)
        let (d, _) = raw(url, headers: miHeaders())
        guard let o = json(d), let arr = o["data"] as? [[String: Any]], !arr.isEmpty else { return }

        let keepVin = vin
        let keepId = carId
        var pick: [String: Any]?
        if !keepVin.isEmpty {
            pick = arr.first { ($0["vin"] as? String) == keepVin }
        }
        if pick == nil, !keepId.isEmpty {
            pick = arr.first { ($0["carId"] as? String) == keepId }
        }
        if pick == nil { pick = arr.first }
        guard let p = pick else { return }

        if let cid = p["carId"] as? String, !cid.isEmpty { carId = cid }
        if let v = p["vin"] as? String, !v.isEmpty { vin = v }
        var name = (p["plateNumber"] as? String) ?? ""
        if name.isEmpty { name = (p["carName"] as? String) ?? "" }
        if !name.isEmpty { carName = name }
        if let sc = p["seriesCode"] as? String { carSeries = sc }

        loadSeriesFromOpen()
    }

    /// 车型代码补齐：开放平台车列表 → 车辆详情
    func loadSeriesFromOpen() {
        let mi = token
        let ot = openToken
        if !mi.isEmpty && tryOpenCarList(mi) { return }
        if !ot.isEmpty && ot != mi && tryOpenCarList(ot) { return }
        if !mi.isEmpty && tryCarInfo(mi) { return }
        if !ot.isEmpty && ot != mi { _ = tryCarInfo(ot) }
    }

    private func tryOpenCarList(_ accessToken: String) -> Bool {
        let path = "/open/api/v1.0/car/getList"
        var p: [String: String] = [:]
        p["accessToken"] = accessToken
        p["pageSize"] = "10"
        p["pageIndex"] = "1"
        p["timestamp"] = "\(Int(Date().timeIntervalSince1970))"
        p["nonce"] = Self.NONCE
        p["appKey"] = Self.CLIENT_SECRET
        let rawStr = p.keys.sorted().map { "\($0)=\(p[$0] ?? "")&" }.joined()
        p["sign"] = sha256(rawStr).uppercased()

        let (d, _) = raw(Self.OPEN_HOST + path, method: "POST", form: p)
        guard let o = json(d) else { return false }
        let code = (o["status_code"] as? Int) ?? (o["statusCode"] as? Int) ?? (o["code"] as? Int) ?? -1
        if code > 0 { return false }
        var arr: [[String: Any]] = []
        if let a = o["data"] as? [[String: Any]] { arr = a }
        else if let dd = o["data"] as? [String: Any] {
            arr = (dd["list"] as? [[String: Any]]) ?? (dd["records"] as? [[String: Any]])
                ?? (dd["cars"] as? [[String: Any]]) ?? (dd["carList"] as? [[String: Any]]) ?? []
        }
        guard !arr.isEmpty else { return false }
        let keepVin = vin
        let keepId = carId
        var pick: [String: Any]?
        if !keepVin.isEmpty { pick = arr.first { ($0["vin"] as? String) == keepVin } }
        if pick == nil, !keepId.isEmpty { pick = arr.first { ($0["carId"] as? String) == keepId } }
        if pick == nil { pick = arr.first }
        return saveSeries(pick)
    }

    private func tryCarInfo(_ accessToken: String) -> Bool {
        let cid = carId
        guard !cid.isEmpty else { return false }
        let path = "/openc-apigw/bdc/api/v1/car/get-carInfo-use-carId"
        let ts = nowMs()
        let q = ["carId": cid]
        var headers: [String: String] = [
            "X-VCS-User-Access-Token": accessToken,
            "X-VCS-Timestamp": "\(ts)",
            "X-VCS-Nonce": Self.NONCE
        ]
        headers["Authorization"] = vcsAuth(method: "GET", path: path, params: q, body: "",
                                           secret: secretKey, timestampMs: ts, headers: headers)
        let (d, _) = raw(Self.OPEN_HOST + path + "?carId=" + Self.urlEncode(cid), headers: headers)
        guard let o = json(d) else { return false }
        let code = (o["status_code"] as? Int) ?? (o["statusCode"] as? Int) ?? (o["code"] as? Int) ?? -1
        if code > 0 { return false }
        let dd = (o["data"] as? [String: Any]) ?? o
        return saveSeries(dd)
    }

    @discardableResult
    private func saveSeries(_ car: [String: Any]?) -> Bool {
        guard let car = car else { return false }
        var series = (car["seriesCode"] as? String) ?? ""
        if series.isEmpty { series = (car["carSeriesCode"] as? String) ?? "" }
        if series.isEmpty { series = (car["vehicleSeriesCode"] as? String) ?? "" }
        if series.isEmpty { series = (car["series"] as? String) ?? "" }
        var seriesName = (car["seriesName"] as? String) ?? ""
        if seriesName.isEmpty { seriesName = (car["carSeriesName"] as? String) ?? "" }
        let v = (car["vin"] as? String) ?? ""
        if series.isEmpty && seriesName.isEmpty && v.isEmpty { return false }
        if !series.isEmpty { carSeries = series }
        if !seriesName.isEmpty { carSeriesName = seriesName }
        if !v.isEmpty { vin = v }
        // 归一化写入，小组件按这个选图
        let code = CarModel.normalize(seriesName.isEmpty ? series : seriesName)
        if !code.isEmpty { carSeries = code }
        else if series.isEmpty { carSeries = seriesName }
        return true
    }

    /// 兼容旧调用
    func loadCar(done: @escaping (Bool, String) -> Void) {
        bg {
            self.loadCars()
            self.legacyRefreshIfNeeded(force: true)
            DispatchQueue.main.async { done(self.isLoggedIn, self.carName) }
        }
    }

    // MARK: - 车况

    /// 拉车况，成功 true（字段时有时无：有才覆盖，保留上次值）
    @discardableResult
    func fetchStatus() -> Bool {
        legacyRefreshIfNeeded(force: false)
        let cid = carId
        guard !cid.isEmpty, !token.isEmpty else { return false }
        let url = Self.MI_HOST + "/app2/api/car/data?carId=" + Self.urlEncode(cid)
            + "&ErrorAutoProjectile=false&toast=false&keys=*&token=" + Self.urlEncode(token) + "&isNev=0"
        let (d0, _) = raw(url, method: "POST", form: [:], headers: miHeaders())
        guard var d = json(d0) else { return false }
        var data = d["data"] as? [String: Any]
        if data == nil, let s = d["data"] as? String, s.hasPrefix("{"),
           let dd = s.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: dd) as? [String: Any] {
            data = o
        }
        guard var body = data else { return false }
        for wrap in ["data", "carCondition", "carData", "result"] {
            if let inner = body[wrap] as? [String: Any] { body = inner }
        }
        d = body

        func num(_ keys: [String]) -> Double {
            for k in keys {
                if let v = d[k] as? Double { return v }
                if let v = d[k] as? Int { return Double(v) }
                if let v = d[k] as? String, let x = Double(v) { return x }
            }
            return -1
        }
        func flag(_ keys: [String]) -> Int {
            let v = num(keys)
            return v < 0 ? -1 : (v == 1 ? 1 : 0)
        }
        /// 任意字段为 1/true 视为开启
        func anyOpen(_ prefix: String) -> Int {
            var seen = false
            for (k, v) in d where k.lowercased().contains(prefix.lowercased()) {
                seen = true
                let sv = "\(v)".lowercased()
                if sv == "1" || sv == "true" || sv == "on" || sv.contains("open") { return 1 }
            }
            return seen ? 0 : -1
        }

        // 续航
        var range = num(["totalResidualMileage"])
        if range <= 0 { range = num(["remainedPowerMile"]) }
        if range <= 0 { range = num(["remainedOilMile"]) }
        if range <= 0 { range = num(["enduranceMileage"]) }
        if range <= 0 { range = num(["range"]) }
        if range > 0 { Prefs.seti(Int(range), "c_range") }

        // 门锁（任一为 1 = 解锁）
        let fl = flag(["driverDoorLock"]), fr = flag(["passengerDoorLock"])
        let rl = flag(["leftRearDoorLock"]), rr = flag(["rightRearDoorLock"])
        let anyUnlock = fl == 1 || fr == 1 || rl == 1 || rr == 1
        Prefs.setb(fl == 1, "c_d_fl"); Prefs.setb(fr == 1, "c_d_fr")
        Prefs.setb(rl == 1, "c_d_rl"); Prefs.setb(rr == 1, "c_d_rr")
        Prefs.setb(!anyUnlock, "c_locked")

        // 车窗
        let wFl = flag(["diverWindow"]), wFr = flag(["passengerWindow"])
        let wRl = flag(["leftRearWindow"]), wRr = flag(["rightRearWindow"])
        let anyWin = wFl == 1 || wFr == 1 || wRl == 1 || wRr == 1
        if wFl >= 0 || wFr >= 0 || wRl >= 0 || wRr >= 0 {
            Prefs.setb(anyWin, "c_win")
            Prefs.setb(wFl == 1, "c_w_fl"); Prefs.setb(wFr == 1, "c_w_fr")
            Prefs.setb(wRl == 1, "c_w_rl"); Prefs.setb(wRr == 1, "c_w_rr")
        }
        let sun = anyOpen("sunroof"); if sun >= 0 { Prefs.setb(sun == 1, "c_sun") }
        let trunk = anyOpen("trunk"); if trunk >= 0 { Prefs.setb(trunk == 1, "c_trunk") }
        let engine = flag(["engineStatus", "fireStatus"])
        if engine >= 0 { Prefs.setb(engine == 1 || engine == 2, "c_engine") }
        let air = flag(["airStatus"]); if air >= 0 { Prefs.setb(air == 1, "c_air") }
        let temp = num(["airConditioningSetTemperature"])
        if temp > 0 { Prefs.seti(Int(temp), "air_temp") }

        // 胎压
        let tpFl = Int(num(["lfTyrePressure", "flTyrePressure"]).rounded())
        let tpFr = Int(num(["rfTyrePressure", "frTyrePressure"]).rounded())
        let tpRl = Int(num(["lrTyrePressure", "rlTyrePressure"]).rounded())
        let tpRr = Int(num(["rrTyrePressure"]).rounded())
        if tpFl > 0 { Prefs.seti(tpFl, "c_tp_fl") }
        if tpFr > 0 { Prefs.seti(tpFr, "c_tp_fr") }
        if tpRl > 0 { Prefs.seti(tpRl, "c_tp_rl") }
        if tpRr > 0 { Prefs.seti(tpRr, "c_tp_rr") }

        // 位置
        func coord(_ keys: [String]) -> Double {
            for k in keys {
                let v = num([k])
                if v != 0 && !v.isNaN { return v }
            }
            return 0
        }
        var lat = coord(["gcjLat", "amapLat", "lat", "latitude"])
        var lng = coord(["gcjLng", "amapLng", "lng", "longitude"])
        if lat == 0 || lng == 0 {
            if let loc = miLocation() {
                lat = loc.0; lng = loc.1
                if !loc.2.isEmpty { Prefs.set(loc.2, "c_addr") }
            }
        }
        if lat != 0 && lng != 0 {
            Prefs.set("\(lat)", "c_lat")
            Prefs.set("\(lng)", "c_lng")
            Prefs.set(String(format: "%.6f,%.6f", lat, lng), "c_geo")
            Prefs.setl(nowMs(), "c_locAt")
        }

        // VIN / 车型
        var v = (d["vin"] as? String) ?? ""
        if v.isEmpty, let ci = d["carInfo"] as? [String: Any] { v = (ci["vin"] as? String) ?? "" }
        var series = (d["seriesCode"] as? String) ?? ""
        if series.isEmpty { series = (d["carSeriesCode"] as? String) ?? "" }
        var name = (d["carName"] as? String) ?? ""
        if name.isEmpty { name = (d["seriesName"] as? String) ?? "" }
        if name.isEmpty { name = (d["carNameForCar"] as? String) ?? "" }
        var code = CarModel.normalize(series)
        if code.isEmpty { code = CarModel.normalize(name) }
        let vinChanged = !v.isEmpty && v != vin
        if !v.isEmpty { vin = v }
        if !code.isEmpty {
            let old = carSeries.uppercased()
            if vinChanged || old.isEmpty || old != code {
                carSeries = code
                if !name.isEmpty { carSeriesName = name }
            }
        }
        Prefs.setl(nowMs(), "c_upd")
        if vinChanged || carSeries.isEmpty { loadSeriesFromOpen() }
        if lat != 0 && lng != 0 { fetchAddress(lat, lng) }

        // 给小组件同步一份
        AppGroupStore.syncFromPrefs()
        return true
    }

    /// 旧 UI 用的车况数据：把缓存拼成字典返回
    func carData(done: @escaping ([String: Any]?) -> Void) {
        bg {
            let ok = self.fetchStatus()
            var out: [String: Any] = [:]
            out["range"] = Prefs.i("c_range")
            out["locked"] = Prefs.b("c_locked")
            out["winOpen"] = Prefs.b("c_win")
            out["sunOpen"] = Prefs.b("c_sun")
            out["engineOn"] = Prefs.b("c_engine")
            out["airOn"] = Prefs.b("c_air")
            out["tpFL"] = Prefs.i("c_tp_fl"); out["tpFR"] = Prefs.i("c_tp_fr")
            out["tpRL"] = Prefs.i("c_tp_rl"); out["tpRR"] = Prefs.i("c_tp_rr")
            out["addr"] = Prefs.s("c_addr")
            out["updatedAt"] = Int(Prefs.l("c_upd"))
            out["series"] = self.carSeries
            out["seriesName"] = self.carSeriesName
            out["carName"] = self.carName
            DispatchQueue.main.async { done(ok ? out : nil) }
        }
    }

    private func miLocation() -> (Double, Double, String)? {
        let cid = carId
        let url = Self.MI_HOST + "/appserver/api/cardata/getCarLocation?carId=" + Self.urlEncode(cid)
            + "&mapType=AMap&loading=false&ErrorAutoProjectile=false&token=" + Self.urlEncode(token)
        let (d, _) = raw(url, method: "POST", form: [:], headers: miHeaders())
        guard let o = json(d), (o["code"] as? Int) == 0,
              let dd = o["data"] as? [String: Any] else { return nil }
        func c(_ keys: [String]) -> Double {
            for k in keys {
                if let v = dd[k] as? Double, v != 0 { return v }
            }
            return 0
        }
        let lat = c(["gcjLat", "lat", "latitude", "amapLat"])
        let lng = c(["gcjLng", "lng", "longitude", "amapLng"])
        var addr = (dd["addrDesc"] as? String) ?? ""
        if addr.isEmpty { addr = (dd["address"] as? String) ?? "" }
        return (lat, lng, addr)
    }

    func location(done: @escaping ([String: Any]?) -> Void) {
        bg {
            _ = self.fetchStatus()
            let lat = Double(Prefs.s("c_lat", "0")) ?? 0
            let lng = Double(Prefs.s("c_lng", "0")) ?? 0
            var out: [String: Any] = [:]
            out["lat"] = lat
            out["lng"] = lng
            out["addr"] = Prefs.s("c_addr")
            out["at"] = Prefs.l("c_locAt")
            DispatchQueue.main.async { done((lat != 0 && lng != 0) ? out : nil) }
        }
    }

    private func fetchAddress(_ lat: Double, _ lng: Double) {
        let url = "https://restapi.amap.com/v3/geocode/regeo?key=\(Self.AMAP_KEY)&location=\(lng),\(lat)&radius=200&extensions=base"
        let (d, _) = raw(url, headers: ["Accept": "application/json"])
        guard let o = json(d), let re = o["regeocode"] as? [String: Any],
              let addr = re["formatted_address"] as? String, !addr.isEmpty else { return }
        Prefs.set(addr, "c_addr")
    }

    // MARK: - 控车

    private var controlBusy = false
    private let controlLock = NSLock()

    /// 指令下发（返回错误文案，nil = 成功）
    func execute(_ cmd: String) -> String? {
        controlLock.lock()
        if controlBusy {
            controlLock.unlock()
            return "上一条指令未完成，请稍后再试"
        }
        controlBusy = true
        controlLock.unlock()
        defer {
            controlLock.lock(); controlBusy = false; controlLock.unlock()
        }

        legacyRefreshIfNeeded(force: false)
        let cid = carId
        guard !cid.isEmpty, !token.isEmpty else { return "未登录，请先登录" }
        var c = cmd
        if c == "SmartLock" || c == "lock_toggle" {
            c = Prefs.b("c_locked") ? "UnLockDoor" : "LockDoor"
        }
        let err = miControl(c, temp: nil)
        if let e = err {
            // 主通道失败 → 老通道备用
            if let e2 = legacyControl(c) { return "\(e)；\(e2)" }
        }
        if c == "LockDoor" || c == "UnLockDoor" {
            Prefs.seti(c == "LockDoor" ? 1 : 0, "lock_expect")
            Prefs.setl(nowMs(), "lock_expect_at")
        }
        Prefs.setl(nowMs(), "last_cmd_at")
        return nil
    }

    func control(cmd: String, done: @escaping (Bool, String) -> Void) {
        bg {
            let err = self.execute(cmd)
            if err == nil { _ = self.fetchStatus() }
            DispatchQueue.main.async { done(err == nil, err ?? "已下发") }
        }
    }

    /// 主通道：取控车码 → 取公钥 → RSA-OAEP → v3/control/execute → 轮询
    private func miControl(_ cmd: String, temp: String?) -> String? {
        let cid = carId
        let f1 = ["token": token]
        let (d1, _) = raw(Self.MI_HOST + "/app2/api/control/createPinVerifyCode",
                          method: "POST", form: f1, headers: miHeaders())
        guard let o1 = json(d1), (o1["code"] as? Int) == 0 else {
            return "获取控车码失败：" + ((json(d1)?["msg"] as? String) ?? "")
        }
        let pvc = (o1["data"] as? String) ?? ""
        let keyUrl = Self.MI_HOST + "/app2/api/v2/security/key?carId=" + Self.urlEncode(cid)
            + "&moblie=&token=" + Self.urlEncode(token)
        let (d2, _) = raw(keyUrl, headers: miHeaders())
        guard let o2 = json(d2), (o2["code"] as? Int) == 0,
              let pub = o2["data"] as? String, !pub.isEmpty else {
            return "获取公钥失败"
        }
        // pinVerifyCode 在源码里是数字或字符串：数字原样，非数字加引号
        let verifyRaw = pvc.range(of: "^[0-9]+$", options: .regularExpression) != nil
            ? pvc : "\"\(pvc.replacingOccurrences(of: "\"", with: "\\\""))\""
        let plain = "{\"pinVerifyCode\":\(verifyRaw),\"cmd\":\"\(cmd)\",\"type\":\"\(cmd)\",\"pin\":\"\(controlPin)\",\"wifiPassword\":\"\"}"
        guard let cipher = RSACrypto.encryptOAEP(plain, publicKeyPEM: pub) else {
            return "加密失败"
        }
        var body = ["carId": cid, "token": token, "isNev": "0", "s": cipher]
        if let t = temp, !t.isEmpty {
            body["temperature"] = t
            body["windPower"] = "7"
            body["airModel"] = "0"
        }
        let (d3, _) = raw(Self.MI_HOST + "/app2/api/v3/control/execute",
                          method: "POST", form: body, headers: miHeaders())
        guard let o3 = json(d3), (o3["code"] as? Int) == 0 else {
            return (json(d3)?["msg"] as? String) ?? "指令发送失败"
        }
        if let dd = o3["data"] as? [String: Any], let tid = dd["taskId"] as? String, !tid.isEmpty {
            Prefs.set(tid, "last_task")
            Prefs.setl(nowMs(), "last_task_at")
            if let e = miPoll(tid) { return e }
        }
        return nil
    }

    /// 轮询执行结果：15 次 × 500ms
    private func miPoll(_ tid: String) -> String? {
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.5)
            let f = ["token": token, "carId": carId, "id": tid, "isNev": "0"]
            let (d, _) = raw(Self.MI_HOST + "/api/car/getControlInfo",
                             method: "POST", form: f, headers: miHeaders())
            guard let o = json(d), (o["code"] as? Int) == 0,
                  let dd = o["data"] as? [String: Any] else { continue }
            let st = (dd["handleStatus"] as? String) ?? ""
            if st == "Completed" { return nil }
            if st == "Failed" || st == "Timeout" {
                return (dd["failReason"] as? String) ?? "车辆未响应"
            }
        }
        return "指令超时，车辆可能离线"
    }

    /// 备用通道（与主通道同链路，独立实现便于排查）
    private func legacyControl(_ cmdValue: String) -> String? {
        let pin = controlPin
        guard !pin.isEmpty else { return "未填控车码" }
        let cid = carId, tk = token
        guard !cid.isEmpty, !tk.isEmpty else { return "备用通道无令牌" }
        let (d1, _) = raw(Self.MI_HOST + "/app2/api/control/createPinVerifyCode",
                          method: "POST", form: ["token": tk], headers: miHeaders())
        guard let o1 = json(d1), (o1["code"] as? Int) == 0,
              let verify = o1["data"] as? String, !verify.isEmpty else { return "备用通道取码失败" }
        let keyUrl = Self.MI_HOST + "/app2/api/v2/security/key?carId=" + Self.urlEncode(cid)
            + "&moblie=&token=" + Self.urlEncode(tk)
        let (d2, _) = raw(keyUrl, headers: miHeaders())
        guard let o2 = json(d2), let pub = o2["data"] as? String, !pub.isEmpty else { return "备用通道取公钥失败" }

        var v = cmdValue
        if let f = v.first { v = f.lowercased() + v.dropFirst() }
        let verifyRaw = verify.range(of: "^[0-9]+$", options: .regularExpression) != nil
            ? verify : "\"\(verify)\""
        let plain = "{\"pinVerifyCode\":\(verifyRaw),\"cmd\":\"\(v)\",\"type\":\"\(v)\",\"pin\":\"\(pin)\",\"wifiPassword\":\"\"}"
        guard let cipher = RSACrypto.encryptOAEP(plain, publicKeyPEM: pub) else { return "备用通道加密失败" }
        let f2 = ["carId": cid, "token": tk, "isNev": "0", "s": cipher]
        let (d3, _) = raw(Self.MI_HOST + "/app2/api/v3/control/execute",
                          method: "POST", form: f2, headers: miHeaders())
        guard let o3 = json(d3) else { return "备用通道无响应" }
        if (o3["code"] as? Int) == 0 { return nil }
        return "备用通道失败 code=\(o3["code"] as? Int ?? -1)"
    }

    // MARK: - 轨迹 / 历史 / 全景

    /// 今日轨迹点（GCJ-02）
    func trackPoints(done: @escaping ([(Double, Double)]) -> Void) {
        bg {
            self.legacyRefreshIfNeeded(force: false)
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let day = df.string(from: Date())
            let url = Self.MI_HOST + "/appserver/api/cardata/historyTrackFromDayTableByDate?carId="
                + Self.urlEncode(self.carId) + "&startDate=" + day + "&endDate=" + day
                + "&loading=false&toast=false&ErrorAutoProjectile=false&token=" + Self.urlEncode(self.token)
            let (d, _) = self.raw(url, method: "POST", form: [:], headers: self.miHeaders())
            var arr: [[String: Any]] = []
            if let o = self.json(d) {
                if let a = o["data"] as? [[String: Any]] { arr = a }
                else if let dd = o["data"] as? [String: Any] {
                    arr = (dd["list"] as? [[String: Any]]) ?? (dd["points"] as? [[String: Any]])
                        ?? (dd["trackList"] as? [[String: Any]]) ?? []
                }
            }
            var pts: [(Double, Double)] = []
            for p in arr {
                func n(_ keys: [String]) -> Double {
                    for k in keys {
                        if let v = p[k] as? Double, v != 0 { return v }
                    }
                    return 0
                }
                let lng = n(["lng", "gcjLng", "longitude"])
                let lat = n(["lat", "gcjLat", "latitude"])
                if lng == 0 || lat == 0 { continue }
                pts.append((lat, lng))
            }
            DispatchQueue.main.async { done(pts) }
        }
    }

    /// 控车记录（近 6 个月）
    func controlHistory(done: @escaping ([[String: Any]]) -> Void) {
        bg {
            self.legacyRefreshIfNeeded(force: false)
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd+HH%3Amm%3Ass"
            let now = Date()
            let start = Calendar.current.date(byAdding: .month, value: -6, to: now) ?? now
            let url = Self.MI_HOST + "/appserver/api/car/getControlActionHistory?carId="
                + Self.urlEncode(self.carId) + "&pageSize=50&page=0&startTime=" + df.string(from: start)
                + "&endTime=" + df.string(from: now)
                + "&toast=false&ErrorAutoProjectile=false&token=" + Self.urlEncode(self.token) + "&isNev=0"
            let (d, _) = self.raw(url, method: "POST", form: [:], headers: self.miHeaders())
            var arr: [[String: Any]] = []
            if let o = self.json(d) {
                if let a = o["data"] as? [[String: Any]] { arr = a }
                else if let dd = o["data"] as? [String: Any] {
                    arr = (dd["data"] as? [[String: Any]]) ?? (dd["list"] as? [[String: Any]]) ?? []
                }
            }
            var out: [[String: Any]] = []
            for it in arr {
                var name = (it["cmdDescription"] as? String) ?? ""
                if name.isEmpty { name = (it["tboxCmd"] as? String) ?? "" }
                if name.isEmpty { name = "控车操作" }
                var st = (it["cmdResult"] as? String) ?? ""
                if st.isEmpty { st = (it["result"] as? String) ?? "" }
                if st.isEmpty { st = (it["cmdStatus"] as? String) ?? "" }
                if st.isEmpty { st = (it["status"] as? String) ?? "" }
                if st.isEmpty { st = (it["successFlag"] as? String) ?? "" }
                out.append(["name": name,
                            "time": (it["cmdSendTime"] as? String) ?? "",
                            "status": st])
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    /// 全景照片列表
    func panorama(done: @escaping ([[String: Any]]) -> Void) {
        bg {
            self.legacyRefreshIfNeeded(force: false)
            let url = Self.MI_HOST + "/appserver/api/file/getMediaFilesByUserIdAndCarId?pageIndex=0&pageSize=20"
                + "&carId=" + Self.urlEncode(self.carId)
                + "&fileType=1&ErrorAutoProjectile=false&token=" + Self.urlEncode(self.token)
                + "&isNev=0&deviceId=" + self.deviceId
            let (d, _) = self.raw(url, method: "POST", form: [:], headers: self.miHeaders())
            var arr: [[String: Any]] = []
            if let o = self.json(d) {
                if let a = o["data"] as? [[String: Any]] { arr = a }
                else if let dd = o["data"] as? [String: Any] {
                    arr = (dd["list"] as? [[String: Any]]) ?? (dd["rows"] as? [[String: Any]])
                        ?? (dd["records"] as? [[String: Any]]) ?? []
                }
            }
            let out = arr.map { p -> [String: Any] in
                var thumb = (p["thumbnail"] as? String) ?? ""
                if thumb.isEmpty { thumb = (p["url"] as? String) ?? "" }
                return ["thumb": thumb,
                        "url": (p["url"] as? String) ?? "",
                        "time": (p["time"] as? String) ?? "",
                        "name": (p["name"] as? String) ?? ""]
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    // MARK: - 其它车务（沿用旧 UI）

    func energy(done: @escaping ([String: Any]?) -> Void) {
        bg {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let d2 = DateFormatter(); d2.dateFormat = "yyyyMMdd"
            let now = Date()
            let q = ["carId": self.carId, "queryType": "0",
                     "date": df.string(from: now), "queryDay": d2.string(from: now),
                     "token": self.token]
            var comps = URLComponents(string: Self.MI_HOST + "/app2/api/car-report/car-energy-trend")!
            comps.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
            let (d, _) = self.raw(comps.url?.absoluteString ?? "", headers: self.miHeaders())
            DispatchQueue.main.async { done(self.json(d)?["data"] as? [String: Any]) }
        }
    }

    func maintenance(done: @escaping ([[String: Any]], [[String: Any]]) -> Void) {
        bg {
            let q1 = ["carId": self.carId, "appVersion": "3.2.0", "token": self.token]
            var c1 = URLComponents(string: Self.MI_HOST + "/mt/uc/api/maintenance/next")!
            c1.queryItems = q1.map { URLQueryItem(name: $0.key, value: $0.value) }
            let (d1, _) = self.raw(c1.url?.absoluteString ?? "", headers: self.miHeaders())
            let adv = ((self.json(d1)?["data"] as? [String: Any])?["advices"] as? [[String: Any]]) ?? []
            let q2 = ["currentPage": "1", "pageSize": "5", "carId": self.carId, "token": self.token]
            var c2 = URLComponents(string: Self.MI_HOST + "/mt/uc/api/maintenance/history")!
            c2.queryItems = q2.map { URLQueryItem(name: $0.key, value: $0.value) }
            let (d2, _) = self.raw(c2.url?.absoluteString ?? "", headers: self.miHeaders())
            let his = ((self.json(d2)?["data"] as? [String: Any])?["list"] as? [[String: Any]]) ?? []
            DispatchQueue.main.async { done(adv, his) }
        }
    }

    func unreadCount(done: @escaping (Int) -> Void) {
        bg {
            var c = URLComponents(string: Self.MI_HOST + "/appserver/api/information/getUnReadInfoNumber")!
            c.queryItems = [URLQueryItem(name: "token", value: self.token)]
            let (d, _) = self.raw(c.url?.absoluteString ?? "", headers: self.miHeaders())
            let n = (self.json(d)?["data"] as? Int)
                ?? ((self.json(d)?["data"] as? [String: Any])?["count"] as? Int) ?? 0
            DispatchQueue.main.async { done(n) }
        }
    }

    func messages(page: Int = 1, size: Int = 20, done: @escaping ([[String: Any]]) -> Void) {
        bg {
            var c = URLComponents(string: Self.MI_HOST + "/appserver/api/information/pageReceiverInfo")!
            c.queryItems = [URLQueryItem(name: "currentPage", value: "\(page)"),
                            URLQueryItem(name: "pageSize", value: "\(size)"),
                            URLQueryItem(name: "token", value: self.token)]
            let (d, _) = self.raw(c.url?.absoluteString ?? "", method: "POST",
                                 form: ["actionType": "1"], headers: self.miHeaders())
            var arr: [[String: Any]] = []
            if let o = self.json(d) {
                if let a = o["data"] as? [[String: Any]] { arr = a }
                else if let dd = o["data"] as? [String: Any] {
                    arr = (dd["records"] as? [[String: Any]]) ?? (dd["list"] as? [[String: Any]])
                        ?? (dd["rows"] as? [[String: Any]]) ?? []
                }
            }
            DispatchQueue.main.async { done(arr) }
        }
    }

    func checkItems(done: @escaping ([[String: Any]]) -> Void) {
        bg {
            var c = URLComponents(string: Self.MI_HOST + "/appserver/api/carcheck/getAllCheckItem")!
            c.queryItems = [URLQueryItem(name: "carId", value: self.carId),
                            URLQueryItem(name: "token", value: self.token)]
            let (d, _) = self.raw(c.url?.absoluteString ?? "", method: "POST", headers: self.miHeaders())
            let arr = (self.json(d)?["data"] as? [[String: Any]]) ?? []
            DispatchQueue.main.async { done(arr) }
        }
    }
}
