import Foundation
import WebKit

/// 拦截 carapp://local/*  ——  静态文件从 App 包内读，/api/* 转发给原生层
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "carapp"
    static let host = "local"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path.isEmpty ? "/index.html" : url.path

        if path.hasPrefix("/api/") {
            handleAPI(path: path, url: url, task: task)
        } else {
            serveStatic(path: path, task: task)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    // MARK: - 静态资源

    private func serveStatic(path: String, task: WKURLSchemeTask) {
        var p = path
        if p == "/" { p = "/index.html" }
        let name = (p as NSString).deletingPathExtension
        let ext = (p as NSString).pathExtension
        let dir = (name as NSString).deletingLastPathComponent
        let base = (name as NSString).lastPathComponent

        guard let file = Bundle.main.path(forResource: base, ofType: ext,
                                          inDirectory: "site" + dir) else {
            reply(task, status: 404, mime: "text/plain", body: Data("404".utf8))
            return
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
            reply(task, status: 500, mime: "text/plain", body: Data("read error".utf8))
            return
        }
        reply(task, status: 200, mime: mime(ext), body: data)
    }

    private func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "woff", "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }

    // MARK: - API 分发

    private func handleAPI(path: String, url: URL, task: WKURLSchemeTask) {
        let api = CarAPI.shared
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func qv(_ k: String) -> String { q.first { $0.name == k }?.value ?? "" }

        // 读请求体（H5 用 POST 传 {phone} 之类）
        var body: [String: Any] = [:]
        if let d = task.request.httpBody ?? readBody(task.request),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            body = o
        }

        func ok(_ dict: [String: Any]) { json(task, dict) }
        func fail(_ msg: String) { json(task, ["success": false, "message": msg]) }

        switch path {
        case "/api/real/session", "/api/real/status":
            if api.isLoggedIn {
                ok(["success": true, "message": "已登录",
                    "car_id": api.carId, "phone": api.phone,
                    "access_token": api.accessToken])
            } else {
                fail("未登录")
            }

        case "/api/real/login":
            let phone = (body["phone"] as? String) ?? qv("phone")
            let code = (body["code"] as? String) ?? qv("code")
            let pin = (body["pin"] as? String) ?? qv("pin")
            api.login(phone: phone, code: code, pin: pin) { success, msg in
                ok(["success": success, "message": msg,
                    "car_id": api.carId, "car_name": "", "phone": phone])
            }

        case "/api/real/sms":
            let phone = (body["phone"] as? String) ?? qv("phone")
            api.sendSms(phone: phone) { success, msg in
                ok(["success": success, "message": msg])
            }

        case "/api/real/cardata", "/api/real/data":
            api.carData { d in
                if let d = d { ok(["success": true, "data": d]) }
                else { fail("取车况失败") }
            }

        case "/api/real/location":
            api.location { d in
                if let d = d {
                    ok(["success": true,
                        "address": d["address"] ?? "", "city": d["city"] ?? "",
                        "lat": d["lat"] ?? 0, "lng": d["lng"] ?? 0,
                        "speed": d["speed"] ?? 0, "gpsTime": d["gpsTime"] ?? ""])
                } else { fail("取位置失败") }
            }

        case "/api/real/energy":
            api.energy { d in
                guard let d = d else { fail("取能耗失败"); return }
                ok(["success": true,
                    "dates": d["dateList"] ?? [], "fuel": d["fuelAvgList"] ?? [],
                    "mileage": d["igniteCumulativeMileage"] ?? [],
                    "fuelAvg": d["fuelAvg"] ?? "", "months": [], "monthFuel": []])
            }

        case "/api/real/maintenance":
            api.maintenance { adv, his in
                let a = adv.map { x -> [String: Any] in
                    ["name": x["maintenanceName"] ?? "", "left": x["remainPercentage"] ?? 0,
                     "nextMileage": x["nextMileage"] ?? 0, "nextDays": x["nextTime"] ?? 0,
                     "advise": x["advise"] ?? ""]
                }
                let h = his.map { x -> [String: Any] in
                    ["items": x["maintainItem"] ?? "", "mile": x["maintainMile"] ?? 0,
                     "time": String((x["maintainTime"] as? String ?? "").prefix(10)),
                     "dealer": x["dealerName"] ?? ""]
                }
                ok(["success": true, "advices": a, "history": h])
            }

        case "/api/real/control", "/api/real/execute":
            let cmd = (body["cmd"] as? String) ?? qv("cmd")
            guard !cmd.isEmpty else { fail("缺少 cmd"); return }
            api.control(cmd: cmd) { success, msg in
                ok(["success": success, "message": msg])
            }

        case "/api/real/online":
            api.carData { d in
                let online = (d?["terminalTime"] as? String) != nil
                ok(["success": true, "online": online,
                    "terminalTime": d?["terminalTime"] ?? ""])
            }

        case "/api/real/unread":
            ok(["success": true, "count": 0])

        case "/api/oil/price":
            let prov = (body["prov"] as? String) ?? qv("prov")
            fetchOil(prov.isEmpty ? "四川" : prov, task: task)

        default:
            // 未实现的接口给个空成功，避免前端弹错
            ok(["success": true, "records": [], "list": [], "items": [],
                "advices": [], "history": [], "count": 0, "groups": []])
        }
    }

    private func readBody(_ req: URLRequest) -> Data? {
        guard let s = req.httpBodyStream else { return nil }
        s.open(); defer { s.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while s.hasBytesAvailable {
            let n = s.read(buf, maxLength: 4096)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data.isEmpty ? nil : data
    }

    // MARK: - 油价

    private func fetchOil(_ prov: String, task: WKURLSchemeTask) {
        let enc = prov.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? prov
        guard let u = URL(string: "https://api.qqsuu.cn/api/dm-oilprice?prov=\(enc)") else {
            json(task, ["success": false]); return
        }
        var req = URLRequest(url: u)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = o["data"] as? [String: Any] else {
                self.json(task, ["success": false]); return
            }
            self.json(task, ["success": true, "prov": d["prov"] ?? prov,
                             "p92": d["p92"] ?? "", "p95": d["p95"] ?? "",
                             "p98": d["p98"] ?? "", "time": d["time"] ?? ""])
        }.resume()
    }

    // MARK: - 响应

    private func json(_ task: WKURLSchemeTask, _ obj: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data("{}".utf8)
        reply(task, status: 200, mime: "application/json; charset=utf-8", body: data)
    }

    private func reply(_ task: WKURLSchemeTask, status: Int, mime: String, body: Data) {
        let h: [String: String] = [
            "Content-Type": mime,
            "Content-Length": "\(body.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store"
        ]
        guard let resp = HTTPURLResponse(url: task.request.url!, statusCode: status,
                                         httpVersion: "HTTP/1.1", headerFields: h) else { return }
        task.didReceive(resp)
        task.didReceive(body)
        task.didFinish()
    }
}
