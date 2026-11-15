import SwiftUI

// MARK: - 操作历史（本地）
struct OpLog: Codable, Identifiable {
    var id = UUID()
    var cmd: String
    var ok: Bool
    var msg: String
    var time: Date
}

enum OpLogStore {
    private static let key = "op_logs_v1"
    static func load() -> [OpLog] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let r = try? JSONDecoder().decode([OpLog].self, from: d) else { return [] }
        return r
    }
    static func append(_ l: OpLog) {
        var list = load()
        list.insert(l, at: 0)
        if list.count > 100 { list = Array(list.prefix(100)) }
        if let d = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - 消息
struct InfoMessage: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let time: String
    let read: Bool
}

// MARK: - 我的
struct MoreView: View {
    @State private var unread = 0
    @State private var messages: [InfoMessage] = []
    @State private var logs: [OpLog] = []
    @State private var showLogout = false
    @State private var loadingMsg = false
    @State private var showPinSheet = false
    @State private var pinInput = ""
    @State private var toast: String?

    private let api = CarAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 账号
                Card {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [
                                    Color(red: 74/255, green: 134/255, blue: 200/255), C.blue
                                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                            Image(systemName: "person.fill")
                                .font(.system(size: 20)).foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(maskedPhone)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(C.txt)
                            Text(api.isLoggedIn ? "已登录 · 长安车联网" : "未登录")
                                .font(.system(size: 11)).foregroundColor(C.muted)
                        }
                        Spacer()
                    }
                }

                // 消息
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("消息")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(C.blue)
                            if unread > 0 {
                                Text("\(unread)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(C.red)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Button { loadMessages() } label: {
                                Text(loadingMsg ? "加载中" : "刷新")
                                    .font(.system(size: 11)).foregroundColor(C.blue)
                            }
                        }
                        if messages.isEmpty {
                            Text(loadingMsg ? "正在拉取…" : "暂无消息")
                                .font(.system(size: 12)).foregroundColor(C.faint)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 14)
                        } else {
                            ForEach(Array(messages.prefix(6).enumerated()), id: \.offset) { i, m in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(m.title)
                                            .font(.system(size: 12.5, weight: m.read ? .regular : .semibold))
                                            .foregroundColor(C.txt).lineLimit(1)
                                        Spacer()
                                        Text(m.time).font(.system(size: 9.5)).foregroundColor(C.faint)
                                    }
                                    if !m.content.isEmpty {
                                        Text(m.content)
                                            .font(.system(size: 11)).foregroundColor(C.muted)
                                            .lineLimit(2)
                                    }
                                }
                                if i < min(5, messages.count - 1) {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                    }
                }

                // 操作历史
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("操作历史")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(C.blue)
                            Spacer()
                            if !logs.isEmpty {
                                Button { OpLogStore.clear(); logs = [] } label: {
                                    Text("清空").font(.system(size: 11)).foregroundColor(C.faint)
                                }
                            }
                        }
                        if logs.isEmpty {
                            Text("暂无操作记录")
                                .font(.system(size: 12)).foregroundColor(C.faint)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 14)
                        } else {
                            ForEach(Array(logs.prefix(10).enumerated()), id: \.offset) { i, l in
                                HStack(spacing: 8) {
                                    Image(systemName: l.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(l.ok ? C.green : C.red)
                                    Text(l.cmd)
                                        .font(.system(size: 12)).foregroundColor(C.txt)
                                    Spacer()
                                    Text(fmtTime(l.time))
                                        .font(.system(size: 9.5)).foregroundColor(C.faint)
                                }
                                if i < min(9, logs.count - 1) {
                                    Divider().opacity(0.3)
                                }
                            }
                        }
                    }
                }

                // 设置
                Card {
                    VStack(spacing: 0) {
                        row("设置控车码", "lock.shield") {
                            pinInput = api.controlPin
                            showPinSheet = true
                        }
                        Divider().opacity(0.4)
                        row("重新登录", "person.badge.key") {
                            CarAPI.shared.accessToken = ""
                            CarAPI.shared.refreshToken = ""
                            CarAPI.shared.carId = ""
                        }
                        Divider().opacity(0.4)
                        row("退出登录", "rectangle.portrait.and.arrow.right", danger: true) {
                            showLogout = true
                        }
                    }
                }

                Text("CarApp · 原生直连长安车联网")
                    .font(.system(size: 10)).foregroundColor(C.faint)
                    .padding(.vertical, 12)

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .background(C.bg.ignoresSafeArea())
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            logs = OpLogStore.load()
            loadUnread()
            if messages.isEmpty { loadMessages() }
        }
        .sheet(isPresented: $showPinSheet) {
            pinSheet
        }
        .confirmationDialog("确定退出登录？", isPresented: $showLogout, titleVisibility: .visible) {
            Button("退出", role: .destructive) { logout() }
            Button("取消", role: .cancel) {}
        }
    }

    private func row(_ title: String, _ icon: String, danger: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(danger ? C.red : C.blue)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundColor(danger ? C.red : C.txt)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundColor(C.faint)
            }
            .padding(.vertical, 12)
        }
    }

    private var pinSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("控车码")
                .font(.system(size: 17, weight: .semibold))
            Text("长安 App 里设置的 6 位安全码")
                .font(.system(size: 12)).foregroundColor(C.muted)
            SecureField("6 位数字", text: $pinInput)
                .keyboardType(.numberPad)
                .padding(12)
                .background(C.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(C.border))
            Button {
                CarAPI.shared.controlPin = pinInput
                showPinSheet = false
            } label: {
                Text("保存")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(C.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
        }
        .padding(22)
        .background(C.bg.ignoresSafeArea())
        .presentationDetents([.height(260)])
    }

    private var maskedPhone: String {
        let p = api.phone
        guard p.count == 11 else { return p.isEmpty ? "未登录" : p }
        return p.prefix(3) + "****" + p.suffix(4)
    }

    private func fmtTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    private func loadUnread() {
        api.unreadCount { n in
            DispatchQueue.main.async { unread = n }
        }
    }

    private func loadMessages() {
        loadingMsg = true
        api.messages { arr in
            var m: [InfoMessage] = []
            for x in arr {
                let title = (x["title"] as? String)
                    ?? (x["msgTitle"] as? String)
                    ?? (x["infoTitle"] as? String) ?? "消息"
                let content = (x["content"] as? String)
                    ?? (x["msgContent"] as? String)
                    ?? (x["infoContent"] as? String) ?? ""
                let t = (x["createTime"] as? String)
                    ?? (x["sendTime"] as? String) ?? ""
                let read = ((x["readFlag"] as? Int) ?? (x["isRead"] as? Int) ?? 0) == 1
                m.append(InfoMessage(title: title, content: content,
                                     time: String(t.suffix(16)), read: read))
            }
            DispatchQueue.main.async {
                messages = m
                loadingMsg = false
            }
        }
    }

    private func logout() {
        api.accessToken = ""
        api.refreshToken = ""
        api.carId = ""
        api.controlPin = ""
        messages = []
        logs = []
        unread = 0
        toast = "已退出"
    }
}
