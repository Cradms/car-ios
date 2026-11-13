import UIKit

/// 原生登录页：手机号 + 短信验证码 + 控车码
final class LoginViewController: UIViewController {

    var onDone: (() -> Void)?

    private let phoneField = UITextField()
    private let codeField = UITextField()
    private let pinField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let loginButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private var countdown = 0
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 243/255, green: 246/255, blue: 250/255, alpha: 1)
        buildUI()
    }

    private func style(_ tf: UITextField, _ placeholder: String, secure: Bool = false, keyboard: UIKeyboardType = .default) {
        tf.placeholder = placeholder
        tf.borderStyle = .none
        tf.backgroundColor = .white
        tf.layer.cornerRadius = 12
        tf.layer.borderWidth = 1
        tf.layer.borderColor = UIColor(red: 230/255, green: 235/255, blue: 241/255, alpha: 1).cgColor
        tf.font = .systemFont(ofSize: 15)
        tf.keyboardType = keyboard
        tf.isSecureTextEntry = secure
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        tf.leftViewMode = .always
        tf.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    private func buildUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 56),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: scroll.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -48)
        ])

        let title = UILabel()
        title.text = "登录长安账号"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = UIColor(red: 26/255, green: 30/255, blue: 36/255, alpha: 1)

        let sub = UILabel()
        sub.text = "使用车机 App 同一手机号，收验证码即可"
        sub.font = .systemFont(ofSize: 13)
        sub.textColor = UIColor(red: 123/255, green: 133/255, blue: 146/255, alpha: 1)
        sub.numberOfLines = 0

        style(phoneField, "手机号", keyboard: .numberPad)
        style(codeField, "短信验证码", keyboard: .numberPad)
        style(pinField, "控车码（6 位，用于控车加密）", secure: true, keyboard: .numberPad)

        // 验证码 + 发送按钮
        let codeRow = UIStackView()
        codeRow.axis = .horizontal
        codeRow.spacing = 8
        codeRow.addArrangedSubview(codeField)
        sendButton.setTitle("获取验证码", for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        sendButton.setTitleColor(UIColor(red: 47/255, green: 111/255, blue: 181/255, alpha: 1), for: .normal)
        sendButton.backgroundColor = .white
        sendButton.layer.cornerRadius = 12
        sendButton.layer.borderWidth = 1
        sendButton.layer.borderColor = UIColor(red: 47/255, green: 111/255, blue: 181/255, alpha: 1).cgColor
        sendButton.widthAnchor.constraint(equalToConstant: 104).isActive = true
        sendButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        sendButton.addTarget(self, action: #selector(onSend), for: .touchUpInside)
        codeRow.addArrangedSubview(sendButton)

        loginButton.setTitle("登录", for: .normal)
        loginButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        loginButton.setTitleColor(.white, for: .normal)
        loginButton.backgroundColor = UIColor(red: 47/255, green: 111/255, blue: 181/255, alpha: 1)
        loginButton.layer.cornerRadius = 12
        loginButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        loginButton.addTarget(self, action: #selector(onLogin), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = UIColor(red: 123/255, green: 133/255, blue: 146/255, alpha: 1)
        statusLabel.numberOfLines = 0

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(sub)
        stack.setCustomSpacing(24, after: sub)
        stack.addArrangedSubview(phoneField)
        stack.addArrangedSubview(codeRow)
        stack.addArrangedSubview(pinField)
        stack.setCustomSpacing(20, after: pinField)
        stack.addArrangedSubview(loginButton)

        let pasteButton = UIButton(type: .system)
        pasteButton.setTitle("已有 token？直接粘贴凭证登录", for: .normal)
        pasteButton.titleLabel?.font = .systemFont(ofSize: 12.5)
        pasteButton.setTitleColor(UIColor(red: 47/255, green: 111/255, blue: 181/255, alpha: 1), for: .normal)
        pasteButton.addTarget(self, action: #selector(onPasteToken), for: .touchUpInside)
        stack.addArrangedSubview(pasteButton)

        stack.addArrangedSubview(statusLabel)
    }

    private func setStatus(_ s: String, error: Bool = false) {
        DispatchQueue.main.async {
            self.statusLabel.text = s
            self.statusLabel.textColor = error
                ? UIColor(red: 214/255, green: 69/255, blue: 69/255, alpha: 1)
                : UIColor(red: 123/255, green: 133/255, blue: 146/255, alpha: 1)
        }
    }

    @objc private func onSend() {
        let phone = (phoneField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard phone.count == 11 else { setStatus("手机号需要 11 位", error: true); return }
        sendButton.isEnabled = false
        setStatus("正在发送…")
        CarAPI.shared.sendSms(phone: phone) { ok, msg in
            self.setStatus(msg, error: !ok)
            if ok { self.startCountdown() }
            else { self.sendButton.isEnabled = true }
        }
    }

    private func startCountdown() {
        countdown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.countdown -= 1
            if self.countdown <= 0 {
                t.invalidate()
                self.sendButton.isEnabled = true
                self.sendButton.setTitle("获取验证码", for: .normal)
            } else {
                self.sendButton.setTitle("\(self.countdown)s", for: .normal)
            }
        }
    }

    @objc private func onLogin() {
        let phone = (phoneField.text ?? "").trimmingCharacters(in: .whitespaces)
        let code = (codeField.text ?? "").trimmingCharacters(in: .whitespaces)
        let pin = (pinField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard phone.count == 11 else { setStatus("手机号需要 11 位", error: true); return }
        guard code.count >= 4 else { setStatus("请填写验证码", error: true); return }
        guard pin.count == 6 else { setStatus("控车码是 6 位数字", error: true); return }

        loginButton.isEnabled = false
        setStatus("登录中…")
        CarAPI.shared.login(phone: phone, code: code, pin: pin) { ok, msg in
            self.loginButton.isEnabled = true
            self.setStatus(msg, error: !ok)
            if ok {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.timer?.invalidate()
                    self.onDone?()
                }
            }
        }
    }

    /// 粘贴格式（任选其一）：
    ///   access|refresh|carId
    ///   或直接贴 data.json 里的 JSON 片段
    @objc private func onPasteToken() {
        let a = UIAlertController(
            title: "粘贴凭证",
            message: "格式：access_token|refresh_token|carId\n也可以直接贴 JSON 片段",
            preferredStyle: .alert)
        a.addTextField { $0.placeholder = "access|refresh|carId"
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no }
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "登录", style: .default) { [weak self] _ in
            guard let self = self,
                  let raw = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return }
            self.applyManualToken(raw)
        })
        present(a, animated: true)
    }

    private func applyManualToken(_ raw: String) {
        var at = "", rt = "", cid = ""
        if raw.contains("{") {
            // JSON 片段
            if let d = raw.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                at = (o["real_access_token"] as? String) ?? (o["access_token"] as? String) ?? ""
                rt = (o["real_refresh_token"] as? String) ?? (o["refresh_token"] as? String) ?? ""
                cid = (o["real_car_id"] as? String) ?? (o["car_id"] as? String) ?? ""
            }
        } else {
            let parts = raw.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3 {
                at = parts[0]; rt = parts[1]; cid = parts[2]
            } else if parts.count == 1 {
                at = parts[0]
            }
        }
        guard !at.isEmpty else { setStatus("没解析出 access_token", error: true); return }

        CarAPI.shared.accessToken = at
        if !rt.isEmpty { CarAPI.shared.refreshToken = rt }
        setStatus("校验中…")
        CarAPI.shared.loadCar { ok, name in
            if ok {
                if !cid.isEmpty { CarAPI.shared.carId = cid }
                self.setStatus("已进入 · \(name)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.timer?.invalidate()
                    self.onDone?()
                }
            } else if !cid.isEmpty {
                // 拉不到车辆但 carId 给了，也放行（token 可能刚好过期）
                CarAPI.shared.carId = cid
                self.setStatus("已保存凭证，进入试试")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.onDone?()
                }
            } else {
                self.setStatus("token 无效或已过期", error: true)
            }
        }
    }

    deinit { timer?.invalidate() }
}
