import SwiftUI

struct LoginView: View {
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var code = ""
    @State private var pin = ""
    @State private var countdown = 0
    @State private var status = ""
    @State private var isError = false
    @State private var busy = false
    @State private var timer: Timer?
    @State private var showTokenSheet = false
    @State private var tokenText = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 头部
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [
                                    Color(red: 74/255, green: 134/255, blue: 200/255),
                                    C.blue
                                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 58, height: 58)
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                        Text("远程控车")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(C.txt)
                        Text("和车机 App 同一账号登录")
                            .font(.system(size: 12.5))
                            .foregroundColor(C.muted)
                    }
                    .padding(.top, 20)

                    // 手机号
                    fieldBox(icon: "phone", placeholder: "手机号", text: $phone, keyboard: .numberPad)

                    // 验证码 + 发送
                    HStack(spacing: 8) {
                        fieldBox(icon: "checkmark.shield", placeholder: "短信验证码", text: $code, keyboard: .numberPad)
                        Button {
                            sendCode()
                        } label: {
                            Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(C.blue)
                                .frame(width: 100, height: 50)
                                .background(C.blue.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(C.blue.opacity(0.28), lineWidth: 1))
                        }
                        .disabled(countdown > 0 || busy)
                    }

                    // 控车码
                    fieldBox(icon: "lock.shield", placeholder: "控车码（6 位，控车加密用）",
                             text: $pin, keyboard: .numberPad, secure: true)

                    // 登录
                    Button {
                        doLogin()
                    } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "登录中…" : "登录")
                                .font(.system(size: 15.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(busy ? C.blue.opacity(0.6)
                                         : C.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .disabled(busy)

                    if !status.isEmpty {
                        Text(status)
                            .font(.system(size: 12))
                            .foregroundColor(isError ? C.red : C.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    Divider().padding(.vertical, 4)

                    Button {
                        showTokenSheet = true
                    } label: {
                        Text("已有 token？直接粘贴")
                            .font(.system(size: 12.5))
                            .foregroundColor(C.blue)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            .background(C.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(C.muted)
                }
            }
            .sheet(isPresented: $showTokenSheet) {
                tokenSheet
            }
        }
    }

    private func fieldBox(icon: String, placeholder: String, text: Binding<String>,
                          keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(C.faint)
                .frame(width: 20)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15))
            .keyboardType(keyboard)
            .autocapitalization(.none)
            .disableAutocorrection(true)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(C.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(C.border, lineWidth: 1))
    }

    private var tokenSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                Text("格式：access_token|refresh_token|carId")
                    .font(.system(size: 11.5)).foregroundColor(C.muted)
                TextEditor(text: $tokenText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 120)
                    .padding(10)
                    .background(C.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(C.border))
                Button {
                    applyToken()
                } label: {
                    Text("使用这组凭证")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(C.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
            }
            .padding(20)
            .background(C.bg.ignoresSafeArea())
            .navigationTitle("粘贴凭证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showTokenSheet = false }
                }
            }
        }
    }

    // MARK: - 动作

    private func sendCode() {
        guard phone.count == 11 else {
            status = "手机号需要 11 位"; isError = true; return
        }
        busy = true
        status = "正在发送…"; isError = false
        CarAPI.shared.sendSms(phone: phone) { ok, msg in
            DispatchQueue.main.async {
                busy = false
                status = msg; isError = !ok
                if ok { startCountdown() }
            }
        }
    }

    private func startCountdown() {
        countdown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                if countdown > 0 { countdown -= 1 }
                else { timer?.invalidate() }
            }
        }
    }

    private func doLogin() {
        guard phone.count == 11 else { status = "手机号需要 11 位"; isError = true; return }
        guard code.count >= 4 else { status = "请填写短信验证码"; isError = true; return }
        guard pin.count == 6 else { status = "控车码是 6 位数字"; isError = true; return }

        busy = true
        status = "登录中…"; isError = false
        CarAPI.shared.login(phone: phone, code: code, pin: pin) { ok, msg in
            DispatchQueue.main.async {
                busy = false
                status = msg; isError = !ok
                if ok {
                    timer?.invalidate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        dismiss()
                        onDone()
                    }
                }
            }
        }
    }

    private func applyToken() {
        let raw = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        var at = "", rt = "", cid = ""
        if raw.contains("{") {
            if let d = raw.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                at = (o["real_access_token"] as? String) ?? (o["access_token"] as? String) ?? ""
                rt = (o["real_refresh_token"] as? String) ?? (o["refresh_token"] as? String) ?? ""
                cid = (o["real_car_id"] as? String) ?? (o["car_id"] as? String) ?? ""
            }
        } else {
            let p = raw.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            if p.count >= 3 { at = p[0]; rt = p[1]; cid = p[2] }
            else if p.count == 1 { at = p[0] }
        }
        guard !at.isEmpty else {
            status = "没解析出 access_token"; isError = true
            showTokenSheet = false
            return
        }
        CarAPI.shared.accessToken = at
        if !rt.isEmpty { CarAPI.shared.refreshToken = rt }
        if !cid.isEmpty { CarAPI.shared.carId = cid }
        showTokenSheet = false
        busy = true
        status = "校验中…"; isError = false
        CarAPI.shared.loadCar { ok, name in
            DispatchQueue.main.async {
                busy = false
                if ok {
                    status = "已登录 · \(name)"
                    dismiss()
                    onDone()
                } else if !cid.isEmpty {
                    status = "凭证已保存，进入后手动刷新"
                    dismiss()
                    onDone()
                } else {
                    status = "token 无效或已过期"; isError = true
                }
            }
        }
    }
}
