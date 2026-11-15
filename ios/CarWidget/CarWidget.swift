import WidgetKit
import SwiftUI
import Security

// MARK: - 共享存储（App Group）
enum Shared {
    static let group = "group.com.yg.carapp"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: group) ?? .standard
    }

    static func str(_ k: String) -> String { defaults.string(forKey: k) ?? "" }
    static func set(_ v: String, _ k: String) { defaults.set(v, forKey: k) }

    static var fuel: String { str("w_fuel") }
    static var range: String {
        let n = defaults.integer(forKey: "w_range")
        return n > 0 ? "\(n)" : ""
    }
    static var odo: String { str("w_odo") }
    static var voltage: String { str("w_voltage") }
    static var carName: String { str("w_car") }
    static var online: Bool { str("w_online") == "1" || defaults.integer(forKey: "w_logged") == 1 }
    static var anyOpen: Bool {
        defaults.integer(forKey: "w_win") == 1 || defaults.integer(forKey: "w_sun") == 1
    }
    static var locked: Bool { defaults.integer(forKey: "w_locked") == 1 }
    static var updated: Date {
        let t = defaults.double(forKey: "w_at")
        return t > 0 ? Date(timeIntervalSince1970: t) : Date(timeIntervalSince1970: 0)
    }

    // 车型（4.5.6 小组件按车型选车模图）
    static var series: String { str("w_series") }
    static var seriesName: String { str("w_series_name") }

    /// 与 CarModel.normalize 对齐（小组件 target 不带 CarModel.swift）
    static func normalize(_ s: String) -> String {
        let u = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if u.isEmpty { return "" }
        if u.contains("逸动") && u.contains("PLUS") { return "C211" }
        if u.contains("启源") && u.contains("A07") { return "C236" }
        if u.contains("UNI-V") { return "C281" }
        if u.contains("启源") && u.contains("A06") { return "C281_P" }
        if u.contains("逸达") { return "C589" }
        if u.contains("启源") && u.contains("A05") { return "C589_P" }
        if u.contains("UNI-K") { return "CD569" }
        if u.contains("UNI-T") { return "S202" }
        if u.contains("CS55") { return "S203" }
        if u.contains("启源") && u.contains("Q05") { return "S203_P" }
        if u.contains("CS75") {
            if u.contains("四代") { return "S311MCA" }
            if u.contains("三代") { return "S311_P" }
            return "S311"
        }
        if u == "C211-1" { return "C211" }
        var v = u
        if let d = v.firstIndex(of: "-"), d != v.startIndex { v = String(v[v.startIndex..<d]) }
        let codes: Set<String> = ["C211", "C236", "C281", "C281_P", "C589", "C589_P",
                                  "CD569", "S202", "S203", "S203_P", "S311", "S311_P", "S311MCA"]
        return codes.contains(v) ? v : ""
    }

    static var modelCode: String {
        let a = normalize(seriesName)
        return a.isEmpty ? normalize(series) : a
    }

    static var carImage: String {
        let c = modelCode
        return c.isEmpty ? "car" : "car_" + c.lowercased()
    }

    static var modelTitle: String {
        switch modelCode {
        case "C211": return "逸动 PLUS"
        case "C236": return "启源 A07"
        case "C281": return "UNI-V"
        case "C281_P": return "启源 A06"
        case "C589": return "逸达 / 逸动"
        case "C589_P": return "启源 A05"
        case "CD569": return "UNI-K"
        case "S202": return "UNI-T"
        case "S203": return "CS55 Plus"
        case "S203_P": return "启源 Q05"
        case "S311": return "CS75 Plus 二代"
        case "S311_P": return "CS75 Plus 三代"
        case "S311MCA": return "CS75 Plus 四代"
        default: return seriesName
        }
    }

    static func saveState(fuel: String, range: String, odo: String, voltage: String,
                          carName: String, online: Bool, anyOpen: Bool, locked: Bool) {
        set(fuel, "w_fuel"); set(range, "w_range"); set(odo, "w_odo")
        set(voltage, "w_voltage"); set(carName, "w_car")
        set(online ? "1" : "0", "w_online")
        set(anyOpen ? "1" : "0", "w_open")
        set(locked ? "1" : "0", "w_locked")
        defaults.set(Date().timeIntervalSince1970, forKey: "w_at")
    }

    // 凭证（与主 App 的 Keychain 同步一份到 App Group，供小组件发指令）
    static var token: String { str("w_token") }
    static var refreshToken: String { str("w_rt") }
    static var carId: String { str("w_cid") }
    static var pin: String { str("w_pin") }
}

// MARK: - 数据
struct Entry: TimelineEntry {
    let date: Date
    let fuel: String
    let range: String
    let odo: String
    let voltage: String
    let carName: String
    let online: Bool
    let anyOpen: Bool
    let locked: Bool
    let updated: Date
    var modelTitle: String = ""
    var carImage: String = "car"
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), fuel: "42", range: "601", odo: "54846",
              voltage: "12.2", carName: "UNI-V", online: true,
              anyOpen: false, locked: true, updated: Date(),
              modelTitle: "UNI-V", carImage: "car_c281")
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let e = current()
        // 15 分钟刷新一次（系统可能延迟）
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func current() -> Entry {
        Entry(date: Date(),
              fuel: Shared.fuel.isEmpty ? "--" : Shared.fuel,
              range: Shared.range.isEmpty ? "--" : Shared.range,
              odo: Shared.odo.isEmpty ? "--" : Shared.odo,
              voltage: Shared.voltage.isEmpty ? "--" : Shared.voltage,
              carName: Shared.carName.isEmpty ? "我的爱车" : Shared.carName,
              online: Shared.online,
              anyOpen: Shared.anyOpen,
              locked: Shared.locked,
              updated: Shared.updated,
              modelTitle: Shared.modelTitle,
              carImage: Shared.carImage)
    }
}

// MARK: - 视图
struct CarWidgetEntryView: View {
    var entry: Entry
    @Environment(\.widgetFamily) var family

    private let blue = Color(red: 47/255, green: 111/255, blue: 181/255)
    private let green = Color(red: 47/255, green: 158/255, blue: 104/255)
    private let red = Color(red: 214/255, green: 69/255, blue: 69/255)
    private let txt = Color(red: 26/255, green: 30/255, blue: 36/255)
    private let muted = Color(red: 123/255, green: 133/255, blue: 146/255)
    private let faint = Color(red: 152/255, green: 162/255, blue: 175/255)

    var body: some View {
        Group {
            switch family {
            case .systemSmall: smallView
            case .systemLarge: largeView
            default: mediumView
            }
        }
        .widgetBackground(Color(red: 243/255, green: 246/255, blue: 250/255))
    }

    // 小尺寸：只放油量 + 续航
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(entry.online ? green : faint).frame(width: 5, height: 5)
                Text(entry.carName).font(.system(size: 11, weight: .semibold))
                    .foregroundColor(txt).lineLimit(1)
                Spacer()
                Image(entry.carImage)
                    .resizable().scaledToFit().frame(height: 20)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(entry.fuel).font(.system(size: 26, weight: .bold)).foregroundColor(txt)
                Text("L").font(.system(size: 10)).foregroundColor(muted)
            }
            HStack(spacing: 2) {
                Text(entry.range).font(.system(size: 14, weight: .semibold)).foregroundColor(blue)
                Text("km").font(.system(size: 9)).foregroundColor(faint)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: entry.locked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 8))
                    .foregroundColor(entry.locked ? green : red)
                Image(systemName: entry.anyOpen ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(entry.anyOpen ? red : green)
                Text(entry.anyOpen ? "有开启" : "全关闭")
                    .font(.system(size: 8.5)).foregroundColor(entry.anyOpen ? red : green)
                Spacer()
            }
        }
        .padding(12)
    }

    // 中尺寸：加三个指标 + 快捷按钮
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(entry.online ? green : faint).frame(width: 5, height: 5)
                Text(entry.carName).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(txt).lineLimit(1)
                if !entry.modelTitle.isEmpty {
                    Text(entry.modelTitle)
                        .font(.system(size: 9)).foregroundColor(muted).lineLimit(1)
                }
                Spacer()
                Text(entry.online ? "在线" : "离线")
                    .font(.system(size: 9)).foregroundColor(faint)
                Image(entry.carImage)
                    .resizable().scaledToFit().frame(height: 30)
            }

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("油量").font(.system(size: 9)).foregroundColor(faint)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(entry.fuel).font(.system(size: 24, weight: .bold)).foregroundColor(txt)
                        Text("L").font(.system(size: 9)).foregroundColor(muted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("续航").font(.system(size: 9)).foregroundColor(faint)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(entry.range).font(.system(size: 24, weight: .bold)).foregroundColor(blue)
                        Text("km").font(.system(size: 9)).foregroundColor(muted)
                    }
                }
            }

            HStack(spacing: 0) {
                miniStat("总里程", entry.odo, "km")
                divider
                miniStat("电压", entry.voltage, "V")
                divider
                miniStat("门窗", entry.anyOpen ? "有开" : "全关", "")
            }

            // 快捷控车（点击打开 App 对应操作，Widget 内不能直接发请求）
            HStack(spacing: 6) {
                quickBtn("锁车", "lock.fill", "LockDoor")
                quickBtn("解锁", "lock.open.fill", "UnLockDoor")
                quickBtn("闪灯", "lightbulb.fill", "FlashLight")
            }
        }
        .padding(12)
    }

    // 大尺寸：中尺寸 + 胎压四角
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            mediumView
            Divider()
            HStack(spacing: 0) {
                miniStat("外温", Shared.str("w_out"), "°C")
                divider
                miniStat("胎压左前", Shared.str("w_lf"), "kPa")
                divider
                miniStat("胎压右前", Shared.str("w_rf"), "kPa")
            }
            Text("更新于 \(fmt(entry.updated))")
                .font(.system(size: 8)).foregroundColor(faint)
        }
        .padding(12)
    }

    private var divider: some View {
        Rectangle().fill(Color(red: 230/255, green: 235/255, blue: 241/255))
            .frame(width: 1, height: 24)
    }

    private func miniStat(_ t: String, _ v: String, _ u: String) -> some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(v).font(.system(size: 11.5, weight: .semibold)).foregroundColor(txt)
                if !u.isEmpty { Text(u).font(.system(size: 8)).foregroundColor(faint) }
            }
            Text(t).font(.system(size: 8)).foregroundColor(faint)
        }
        .frame(maxWidth: .infinity)
    }

    private func quickBtn(_ t: String, _ icon: String, _ cmd: String) -> some View {
        Link(destination: URL(string: "carapp://action?cmd=\(cmd)")!) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 12))
                Text(t).font(.system(size: 8.5))
            }
            .foregroundColor(blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Widget 背景兼容
extension View {
    @ViewBuilder
    func widgetBackground(_ bg: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(bg, for: .widget)
        } else {
            background(bg)
        }
    }
}

// MARK: - Widget 声明
@main
struct CarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CarWidget", provider: Provider()) { entry in
            CarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("车况")
        .description("油量、续航、门窗状态，支持快捷控车")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
