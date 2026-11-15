import Foundation

/// 车型归一化（与源码 CarModelImage.normalize 一致）
///
/// 车架号/车名 → 车型代码 → 车模图 + 中文名。
enum CarModel {

    struct Item {
        let code: String
        let name: String
        var image: String { "car_" + code.lowercased() }
    }

    static let all: [Item] = [
        Item(code: "C211", name: "逸动 PLUS"),
        Item(code: "C236", name: "启源 A07"),
        Item(code: "C281", name: "UNI-V"),
        Item(code: "C281_P", name: "启源 A06"),
        Item(code: "C589", name: "逸达 / 逸动"),
        Item(code: "C589_P", name: "启源 A05"),
        Item(code: "CD569", name: "UNI-K"),
        Item(code: "S202", name: "UNI-T"),
        Item(code: "S203", name: "CS55 Plus"),
        Item(code: "S203_P", name: "启源 Q05"),
        Item(code: "S311", name: "CS75 Plus 二代"),
        Item(code: "S311_P", name: "CS75 Plus 三代"),
        Item(code: "S311MCA", name: "CS75 Plus 四代")
    ]

    private static let codes = Set(all.map { $0.code })

    /// 别名 → 归一化（去 -1 等后缀）→ 白名单兜底
    static func normalize(_ series: String) -> String {
        var s = series.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.isEmpty { return "" }
        if s.contains("逸动") && s.contains("PLUS") { return "C211" }
        if s.contains("启源") && s.contains("A07") { return "C236" }
        if s.contains("UNI-V") { return "C281" }
        if s.contains("启源") && s.contains("A06") { return "C281_P" }
        if s.contains("逸达") { return "C589" }
        if s.contains("启源") && s.contains("A05") { return "C589_P" }
        if s.contains("UNI-K") { return "CD569" }
        if s.contains("UNI-T") { return "S202" }
        if s.contains("CS55") { return "S203" }
        if s.contains("启源") && s.contains("Q05") { return "S203_P" }
        if s.contains("CS75") {
            if s.contains("四代") { return "S311MCA" }
            if s.contains("三代") { return "S311_P" }
            return "S311"
        }
        if s == "C211-1" { return "C211" }
        if let dash = s.firstIndex(of: "-"), dash != s.startIndex {
            s = String(s[s.startIndex..<dash])
        }
        return codes.contains(s) ? s : ""
    }

    static func name(_ code: String) -> String {
        all.first { $0.code == code }?.name ?? ""
    }

    /// 小组件/首页用图：命中车型用专属图，否则通用图
    static func image(_ code: String) -> String {
        let c = normalize(code)
        return c.isEmpty ? "car" : "car_" + c.lowercased()
    }
}
