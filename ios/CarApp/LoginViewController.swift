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

    deinit { timer?.invalidate() }
}
