import Foundation

/// 长安车联网接口（原生直连，不经过自建服务器）
final class CarAPI {

    static let shared = CarAPI()

    private let host = "https://m.iov.changan.com.cn"
    private let UA = "ChanganInCall/5.2.0 (iPhone; iOS 15.0; Scale/3.00)"
    private let clientId = "2c918082632162010163388048d60158"
    private let deviceId = "00000000-5768-bcb8-ffff-ffffef05ac4a"

    private var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 30
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    // MARK: - 登录态

    var accessToken: String {
        get { TokenStore.get("access_token") ?? "" }
        set { TokenStore.set(newValue, for: "access_token") }
    }
    var refreshToken: String {
        get { TokenStore.get("refresh_token") ?? "" }
        set { TokenStore.set(newValue, for: "refresh_token") }
    }
    var carId: String {
        get { TokenStore.get("car_id") ?? "" }
        set { TokenStore.set(newValue, for: "car_id") }
    }
    var phone: String {
        get { TokenStore.get("phone") ?? "" }
        set { TokenStore.set(newValue, for: "phone") }
    }
    var controlPin: String {
        get { TokenStore.get("pin") ?? "" }
        set { TokenStore.set(newValue, for: "pin") }
    }
    var isLoggedIn: Bool { !accessToken.isEmpty && !carId.isEmpty }

    // MARK: - 基础请求

    private func headers(extra: [String: String] = [:]) -> [String: String] {
        var h: [String: String] = [
            "Accept": "application/json, text/plain, */*",
            "User-Agent": UA,
            "X-Requested-With": "cn.com.changan.cvim",
            "vcs-app-id": "inCall"
        ]
        extra.forEach { h[$0.key] = $0.value }
        return h
    }

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL? {
        guard var comps = URLComponents(string: host + path) else { return nil }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url
    }

    private func request(_ path: String,
                         query: [String: String] = [:],
                         method: String = "GET",
                         form: [String: String]? = nil,
                         retry: Int = 1,
                         done: @escaping ([String: Any]?) -> Void) {
        guard let u = url(path, query) else { done(nil); return }
        var req = URLRequest(url: u)
        req.httpMethod = method
        if let f = form {
            var comps = URLComponents()
            comps.queryItems = f.map { URLQueryItem(name: $0.key, value: $0.value) }
            req.httpBody = (comps.percentEncodedQuery ?? "").data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        }
        headers().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        session.dataTask(with: req) { data, resp, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                done(nil); return
            }
            let code = (obj["code"] as? Int) ?? (obj["status_code"] as? Int) ?? -1
            // token 失效 → 刷新后重试一次
            if (code == 2 || code == 401) && retry > 0 {
                CarAPI.shared.refresh { ok in
                    if ok { self.request(path, query: query, method: method, form: form,
                                         retry: retry - 1, done: done) }
                    else { done(obj) }
                }
                return
            }
            done(obj)
        }.resume()
    }

    // MARK: - 登录

    func sendSms(phone: String, done: @escaping (Bool, String) -> Void) {
        request("/api/sms/sendAuthcode", method: "POST", form: ["phone": phone]) { obj in
            let ok = (obj?["success"] as? Bool) ?? false
            done(ok, (obj?["msg"] as? String) ?? (ok ? "验证码已发送" : "发送失败"))
        }
    }

    func login(phone: String, code: String, pin: String,
               done: @escaping (Bool, String) -> Void) {
        request("/app2/api/oauth2login/token/stageOne",
                method: "POST", form: ["mobile": phone, "vercode": code]) { obj in
            let data = (obj?["data"] as? [String: Any]) ?? [:]
            let at = (data["access_token"] as? String) ?? ""
            let rt = (data["refresh_token"] as? String) ?? ""
            guard !at.isEmpty else {
                done(false, (obj?["msg"] as? String) ?? "验证码错误或已过期")
                return
            }
            self.accessToken = at
            self.refreshToken = rt
            self.phone = phone
            if !pin.isEmpty { self.controlPin = pin }
            self.loadCar { ok, name in
                done(ok, ok ? "登录成功 · \(name)" : "登录成功，但没取到车辆")
            }
        }
    }

    func refresh(done: @escaping (Bool) -> Void) {
        let rt = refreshToken
        guard !rt.isEmpty else { done(false); return }
        let s = "https://incallapi.changan.com.cn/cac/api/v1/oauth2/refresh_token?client_id=\(clientId)&refresh_token=\(rt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        var req = URLRequest(url: URL(string: s)!)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("okhttp/4.9.0", forHTTPHeaderField: "User-Agent")
        req.setValue("json", forHTTPHeaderField: "response-form")
        session.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                done(false); return
            }
            let at = (obj["access_token"] as? String)
                ?? ((obj["data"] as? [String: Any])?["access_token"] as? String) ?? ""
            let nrt = (obj["refresh_token"] as? String)
                ?? ((obj["data"] as? [String: Any])?["refresh_token"] as? String) ?? rt
            if at.isEmpty { done(false); return }
            self.accessToken = at
            self.refreshToken = nrt
            done(true)
        }.resume()
    }

    /// 有 token 就先直接用，失败再用 refresh_token 换
    func refreshIfNeeded(done: @escaping (Bool) -> Void) {
        guard !accessToken.isEmpty else { done(false); return }
        // 先试探一次（能拿到车就说明有效）
        carData { d in
            if d != nil { done(true); return }
            self.refresh { ok in done(ok) }
        }
    }

    func loadCar(done: @escaping (Bool, String) -> Void) {
        request("/app2/api/user/cars", query: ["type": "0", "token": accessToken]) { obj in
            let arr = (obj?["data"] as? [[String: Any]]) ?? []
            guard let row = arr.first else { done(false, ""); return }
            let cid = (row["carId"] as? String) ?? ""
            let name = (row["carName"] as? String) ?? "我的爱车"
            if !cid.isEmpty { self.carId = cid }
            done(!cid.isEmpty, name)
        }
    }

    // MARK: - 车况

    func carData(done: @escaping ([String: Any]?) -> Void) {
        request("/app2/api/car/data",
                query: ["carId": carId, "ErrorAutoProjectile": "false", "toast": "false",
                        "keys": "*", "isNev": "0", "token": accessToken],
                method: "POST") { obj in
            done(obj?["data"] as? [String: Any])
        }
    }

    func location(done: @escaping ([String: Any]?) -> Void) {
        request("/app2/api/car/location",
                query: ["carId": carId, "mapType": "GCJ02", "ErrorAutoProjectile": "false",
                        "toast": "false", "token": accessToken, "isNev": "0",
                        "deviceId": deviceId]) { obj in
            done(obj?["data"] as? [String: Any])
        }
    }

    func energy(done: @escaping ([String: Any]?) -> Void) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let d2 = DateFormatter(); d2.dateFormat = "yyyyMMdd"
        let now = Date()
        request("/app2/api/car-report/car-energy-trend",
                query: ["carId": carId, "queryType": "0",
                        "date": df.string(from: now), "queryDay": d2.string(from: now),
                        "token": accessToken]) { obj in
            done(obj?["data"] as? [String: Any])
        }
    }

    func maintenance(done: @escaping ([[String: Any]], [[String: Any]]) -> Void) {
        request("/mt/uc/api/maintenance/next",
                query: ["carId": carId, "appVersion": "3.2.0", "token": accessToken]) { obj in
            let adv = ((obj?["data"] as? [String: Any])?["advices"] as? [[String: Any]]) ?? []
            self.request("/mt/uc/api/maintenance/history",
                         query: ["currentPage": "1", "pageSize": "5",
                                 "carId": self.carId, "token": self.accessToken]) { o2 in
                let his = ((o2?["data"] as? [String: Any])?["list"] as? [[String: Any]]) ?? []
                done(adv, his)
            }
        }
    }

    // MARK: - 控车

    /// 下发一条控车指令（内部完成：取 pinVerifyCode → 取公钥 → RSA 加密 → 下发）
    func control(cmd: String, done: @escaping (Bool, String) -> Void) {
        let pin = controlPin
        guard !pin.isEmpty else { done(false, "请先设置控车码"); return }
        guard !accessToken.isEmpty, !carId.isEmpty else { done(false, "请先登录"); return }

        let cid = carId, at = accessToken
        // 1) pinVerifyCode
        request("/app2/api/control/createPinVerifyCode",
                query: ["carId": cid, "token": at, "isNev": "0"],
                method: "POST") { pv in
            let code = (pv?["data"] as? String) ?? ""
            // 2) 公钥
            self.request("/app2/api/v2/security/key",
                         query: ["carId": cid, "token": at]) { keyObj in
                guard let pub = keyObj?["data"] as? String, !pub.isEmpty else {
                    done(false, "取公钥失败"); return
                }
                // 3) RSA-OAEP 加密
                let payload: [String: Any] = ["cmd": cmd, "type": cmd,
                                              "pin": pin, "pinVerifyCode": code]
                guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
                      let plain = String(data: json, encoding: .utf8),
                      let cipher = RSACrypto.encryptOAEP(plain, publicKeyPEM: pub) else {
                    done(false, "加密失败"); return
                }
                // 4) 下发
                self.request("/app2/api/v3/control/execute",
                             method: "POST",
                             form: ["carId": cid, "token": at, "isNev": "0", "s": cipher]) { r in
                    let ok = (r?["success"] as? Bool) ?? false
                    done(ok, (r?["msg"] as? String) ?? (ok ? "已下发" : "下发失败"))
                }
            }
        }
    }
}
