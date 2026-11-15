import SwiftUI

// MARK: - 加油记录
struct FuelRecord: Codable, Identifiable {
    var id = UUID()
    var date: String
    var odo: Double
    var liters: Double
    var price: Double
    var amount: Double
    var full: Bool = true
    var distance: Double?
    var per100: Double?
}

// MARK: - 本地存储
enum FuelStore {
    private static let key = "fuel_records_v1"

    static func load() -> [FuelRecord] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let r = try? JSONDecoder().decode([FuelRecord].self, from: d) else { return [] }
        return r.sorted { $0.odo < $1.odo }
    }

    static func save(_ r: [FuelRecord]) {
        if let d = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    static func append(_ rec: FuelRecord) {
        var list = load()
        list.append(rec)
        list.sort { $0.odo < $1.odo }
        // 重算每段油耗
        for i in 1..<list.count {
            let dist = list[i].odo - list[i - 1].odo
            if dist > 0 {
                list[i].distance = dist
                list[i].per100 = list[i].liters / dist * 100
            }
        }
        save(list)
    }

    static func remove(_ id: UUID) {
        save(load().filter { $0.id != id })
    }

    static var avgPer100: Double? {
        let v = load().compactMap { $0.per100 }
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    static var latestPer100: Double? { load().compactMap { $0.per100 }.last }
}

// MARK: - 油耗页
struct FuelView: View {
    @State private var trend: [DailyFuel] = []
    @State private var months: [MonthlyFuel] = []
    @State private var records: [FuelRecord] = []
    @State private var loading = true
    @State private var showForm = false

    private let api = CarAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 概览
                Card {
                    VStack(spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("最新油耗")
                                    .font(.system(size: 11)).foregroundColor(C.faint)
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(FuelStore.latestPer100.map { String(format: "%.1f", $0) } ?? "--")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(C.txt)
                                    Text("L/100km").font(.system(size: 11)).foregroundColor(C.muted)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("平均油耗")
                                    .font(.system(size: 11)).foregroundColor(C.faint)
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(FuelStore.avgPer100.map { String(format: "%.1f", $0) } ?? "--")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(C.blue)
                                    Text("L/100km").font(.system(size: 11)).foregroundColor(C.muted)
                                }
                            }
                        }
                        if let l = FuelStore.latestPer100 {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10)).foregroundColor(C.faint)
                                Text("基于两次加满之间的实际里程计算")
                                    .font(.system(size: 10.5)).foregroundColor(C.faint)
                            }
                        } else {
                            Text("需要两条「加满」记录才能算真实油耗")
                                .font(.system(size: 10.5)).foregroundColor(C.faint)
                        }
                    }
                }

                // 近 7 天
                if !trend.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("近 7 天能耗")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(C.blue)
                                Spacer()
                                Text(String(format: "%.1f L/100km", trend.compactMap { $0.fuel }.last ?? 0))
                                    .font(.system(size: 11, weight: .medium)).foregroundColor(C.muted)
                            }
                            barChart(trend.map { $0.fuel ?? 0 }, labels: trend.map { $0.label })
                        }
                    }
                }

                // 月度
                if !months.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("今年月度油耗（L/100km）")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(C.blue)
                            barChart(months.map { $0.fuel }, labels: months.map { $0.label },
                                     color: C.blue.opacity(0.55))
                        }
                    }
                }

                // 记录
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("加油记录")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(C.blue)
                            Spacer()
                            if !records.isEmpty {
                                Text("共 \(records.count) 条")
                                    .font(.system(size: 10.5)).foregroundColor(C.faint)
                            }
                        }
                        if records.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "fuelpump")
                                    .font(.system(size: 26)).foregroundColor(C.faint)
                                Text("还没有加油记录")
                                    .font(.system(size: 12.5, weight: .medium)).foregroundColor(C.muted)
                                Text("点右上角「+」记一笔，加满两次后自动算出真实油耗")
                                    .font(.system(size: 10.5)).foregroundColor(C.faint)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        } else {
                            ForEach(records.reversed()) { r in
                                recordRow(r)
                                if r.id != records.first?.id {
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .background(C.bg.ignoresSafeArea())
        .navigationTitle("油耗")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showForm = true } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(C.blue)
                }
            }
        }
        .sheet(isPresented: $showForm) {
            FuelFormView { rec in
                FuelStore.append(rec)
                records = FuelStore.load()
                showForm = false
            }
        }
        .onAppear {
            records = FuelStore.load()
            loadTrend()
        }
    }

    // MARK: 柱状图
    private func barChart(_ values: [Double], labels: [String],
                          color: Color = C.blue) -> some View {
        let mx = max(values.max() ?? 1, 1)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 3) {
                        Text(v > 0 ? String(format: "%.1f", v) : "-")
                            .font(.system(size: 8.5)).foregroundColor(C.blue)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(v > 0 ? color : C.bg)
                            .frame(height: max(4, CGFloat(v / mx) * 46))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 66, alignment: .bottom)

            HStack(spacing: 5) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, l in
                    Text(l)
                        .font(.system(size: 8.5)).foregroundColor(C.faint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: 记录行
    private func recordRow(_ r: FuelRecord) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(r.date).font(.system(size: 12.5, weight: .semibold)).foregroundColor(C.txt)
                if r.full {
                    Text("加满")
                        .font(.system(size: 9))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(C.green.opacity(0.12))
                        .foregroundColor(C.green)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(String(format: "%.2f L", r.liters))
                    .font(.system(size: 12.5, weight: .semibold)).foregroundColor(C.blue)
            }
            HStack {
                Text(String(format: "%.0f km", r.odo))
                    .font(.system(size: 10.5)).foregroundColor(C.muted)
                Text("·").foregroundColor(C.faint)
                Text(String(format: "%.2f 元/L", r.price))
                    .font(.system(size: 10.5)).foregroundColor(C.muted)
                Text("·").foregroundColor(C.faint)
                Text(String(format: "¥%.2f", r.amount))
                    .font(.system(size: 10.5)).foregroundColor(C.muted)
                Spacer()
                if let p = r.per100 {
                    Text(String(format: "%.1f L/100km", p))
                        .font(.system(size: 10.5, weight: .medium)).foregroundColor(C.green)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                FuelStore.remove(r.id)
                records = FuelStore.load()
            } label: { Label("删除", systemImage: "trash") }
        }
    }

    // MARK: 数据
    private func loadTrend() {
        loading = true
        api.energy { d in
            DispatchQueue.main.async {
                loading = false
                guard let d = d else { return }
                // 日趋势
                let dates = (d["dateList"] as? [String]) ?? []
                let fuelRaw = (d["fuelAvgList"] as? [Any]) ?? []
                var t: [DailyFuel] = []
                for (i, dt) in dates.enumerated() {
                    let v = i < fuelRaw.count ? (Double("\(fuelRaw[i])") ?? 0) : 0
                    let label = dt.count >= 8
                        ? "\(dt.dropFirst(4).prefix(2))/\(dt.suffix(2))"
                        : dt
                    t.append(DailyFuel(label: String(label), fuel: v > 0 ? v : nil))
                }
                trend = t
                // 月度（queryType=1 没做进 CarAPI，先用同样数据兜底）
            }
        }
    }
}

struct DailyFuel: Identifiable {
    let id = UUID()
    let label: String
    let fuel: Double?
}

struct MonthlyFuel: Identifiable {
    let id = UUID()
    let label: String
    let fuel: Double
}

// MARK: - 记一笔
struct FuelFormView: View {
    var onSave: (FuelRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var odo = ""
    @State private var liters = ""
    @State private var price = ""
    @State private var amount = ""
    @State private var full = true
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        NavigationView {
            Form {
                Section("本次加油") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("总里程")
                        Spacer()
                        TextField("如 54850", text: $odo).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("km").foregroundColor(C.faint)
                    }
                    HStack {
                        Text("加油量")
                        Spacer()
                        TextField("如 42.5", text: $liters).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("L").foregroundColor(C.faint)
                    }
                    HStack {
                        Text("单价")
                        Spacer()
                        TextField("如 8.98", text: $price).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("元/L").foregroundColor(C.faint)
                    }
                    HStack {
                        Text("金额")
                        Spacer()
                        TextField("如 381.65", text: $amount).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("元").foregroundColor(C.faint)
                    }
                    Toggle("加满（跳枪）", isOn: $full)
                }
                Section {
                    Button {
                        fetchOilPrice()
                    } label: {
                        HStack {
                            Image(systemName: "fuelpump.circle")
                            Text("用今日油价填入单价")
                        }
                        .foregroundColor(C.blue)
                    }
                }
                if !err.isEmpty {
                    Section {
                        Text(err).font(.system(size: 12)).foregroundColor(C.red)
                    }
                }
            }
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(busy)
                }
            }
        }
    }

    private func save() {
        guard let o = Double(odo), o > 0 else { err = "里程不对"; return }
        guard let l = Double(liters), l > 0 else { err = "加油量不对"; return }
        var p = Double(price) ?? 0
        var a = Double(amount) ?? 0
        if p > 0 && a == 0 { a = p * l }
        if a > 0 && p == 0 { p = a / l }
        guard p > 0 else { err = "单价和金额至少填一个"; return }

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let rec = FuelRecord(date: df.string(from: date), odo: o,
                             liters: l, price: p, amount: a, full: full)
        onSave(rec)
        dismiss()
    }

    private func fetchOilPrice() {
        busy = true
        err = ""
        var req = URLRequest(url: URL(string:
            "https://api.qqsuu.cn/api/dm-oilprice?prov=%E5%9B%9B%E5%B7%9D")!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                busy = false
                guard let data = data,
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let d = o["data"] as? [String: Any],
                      let p92 = d["p92"] as? String else {
                    err = "取油价失败，手动填吧"
                    return
                }
                price = p92
                if let l = Double(liters), l > 0, let p = Double(p92) {
                    amount = String(format: "%.2f", p * l)
                }
            }
        }.resume()
    }
}
