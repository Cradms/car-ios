import SwiftUI

struct MaintainAdvice: Identifiable {
    let id = UUID()
    let name: String
    let pct: Double
    let nextMileage: String
    let nextDays: String
}

struct MaintainHistory: Identifiable {
    let id = UUID()
    let items: String
    let mile: String
    let date: String
    let dealer: String
}

struct CheckGroup: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let items: [String]
}

struct MaintainView: View {
    @State private var advices: [MaintainAdvice] = []
    @State private var history: [MaintainHistory] = []
    @State private var groups: [CheckGroup] = []
    @State private var loading = true
    @State private var errMsg: String?

    private let api = CarAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if loading {
                    ProgressView().padding(.top, 60)
                } else {
                    // 保养建议
                    if !advices.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("保养进度")
                                        .font(.system(size: 12, weight: .semibold)).foregroundColor(C.blue)
                                    Spacer()
                                    if let worst = advices.min(by: { $0.pct < $1.pct }) {
                                        Text(worst.pct < 10 ? "需尽快处理" : "状态正常")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(worst.pct < 10 ? C.red : C.green)
                                    }
                                }
                                ForEach(advices) { a in
                                    adviceRow(a)
                                }
                            }
                        }
                    }

                    // 最近保养
                    if !history.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("最近保养")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(C.blue)
                                ForEach(Array(history.prefix(3).enumerated()), id: \.offset) { i, h in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(i == 0 ? C.blue : C.faint)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 5)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(h.items)
                                                .font(.system(size: 12)).foregroundColor(C.txt)
                                                .lineLimit(2)
                                            Text("\(h.date)  ·  \(h.mile) km")
                                                .font(.system(size: 10)).foregroundColor(C.faint)
                                        }
                                        Spacer()
                                    }
                                    if i < min(2, history.count - 1) {
                                        Divider().opacity(0.35).padding(.leading, 14)
                                    }
                                }
                            }
                        }
                    }

                    // 车辆自检
                    if !groups.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("车辆自检")
                                        .font(.system(size: 12, weight: .semibold)).foregroundColor(C.blue)
                                    Spacer()
                                    Text("共 \(groups.count) 个系统")
                                        .font(.system(size: 10.5)).foregroundColor(C.faint)
                                }
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                                          spacing: 8) {
                                    ForEach(groups) { g in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 5) {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .font(.system(size: 11)).foregroundColor(C.green)
                                                Text(g.name)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(C.txt)
                                            }
                                            Text("\(g.count) 项检查")
                                                .font(.system(size: 10)).foregroundColor(C.faint)
                                            if !g.items.isEmpty {
                                                Text(g.items.prefix(3).joined(separator: " · "))
                                                    .font(.system(size: 9.5)).foregroundColor(C.faint)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(C.bg)
                                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    }
                                }
                            }
                        }
                    }

                    if let e = errMsg, advices.isEmpty && groups.isEmpty {
                        Card {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(C.amber)
                                Text(e).font(.system(size: 12.5)).foregroundColor(C.muted)
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
        .navigationTitle("维保")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { load() } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(C.blue)
                }
            }
        }
        .onAppear { load() }
    }

    private func adviceRow(_ a: MaintainAdvice) -> some View {
        let warn = a.pct < 10
        let low = a.pct < 30
        let color = warn ? C.red : (low ? C.amber : C.green)
        return VStack(spacing: 5) {
            HStack {
                Text(a.name)
                    .font(.system(size: 12.5)).foregroundColor(C.txt)
                    .lineLimit(1)
                Spacer()
                Text(a.pct <= 0 ? "已过期" : String(format: "剩 %.0f%%", a.pct))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(C.bg)
                    Capsule().fill(color)
                        .frame(width: g.size.width * CGFloat(min(100, max(0, a.pct))) / 100)
                }
            }
            .frame(height: 5)
            HStack(spacing: 4) {
                Text("下次 \(a.nextMileage) km")
                Text("·")
                Text("\(a.nextDays) 天后")
                Spacer()
            }
            .font(.system(size: 9.5))
            .foregroundColor(C.faint)
        }
    }

    private func load() {
        loading = true
        errMsg = nil
        api.maintenance { adv, his in
            var a: [MaintainAdvice] = []
            for x in adv {
                let name = (x["maintenanceName"] as? String) ?? "保养项"
                let pct: Double = {
                    if let v = x["remainPercentage"] as? Double { return v }
                    if let v = x["remainPercentage"] as? Int { return Double(v) }
                    if let v = x["remainPercentage"] as? String { return Double(v) ?? 0 }
                    return 0
                }()
                let nm = "\(x["nextMileage"] ?? 0)"
                let nd = "\(x["nextTime"] ?? 0)"
                a.append(MaintainAdvice(name: name, pct: pct,
                                        nextMileage: nm, nextDays: nd))
            }
            var h: [MaintainHistory] = []
            for x in his {
                let items = (x["maintainItem"] as? String) ?? "保养"
                let mile = "\(x["maintainMile"] ?? 0)"
                let t = (x["maintainTime"] as? String) ?? ""
                let dealer = (x["dealerName"] as? String) ?? ""
                h.append(MaintainHistory(items: items, mile: mile,
                                         date: String(t.prefix(10)), dealer: dealer))
            }
            DispatchQueue.main.async {
                advices = a
                history = h
                loading = false
                loadChecks()
            }
        }
    }

    private func loadChecks() {
        api.checkItems { arr in
            var gs: [CheckGroup] = []
            for g in arr {
                let name = (g["nodeName"] as? String) ?? ""
                let kids = (g["child"] as? [[String: Any]]) ?? []
                let names = kids.compactMap { $0["nodeName"] as? String }
                gs.append(CheckGroup(name: name, count: kids.count, items: names))
            }
            DispatchQueue.main.async {
                groups = gs
                if advices.isEmpty && gs.isEmpty { errMsg = "保养与自检数据都为空" }
            }
        }
    }
}
