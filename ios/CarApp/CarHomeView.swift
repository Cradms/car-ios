import SwiftUI

// MARK: - 主题色
enum C {
    static let bg     = Color(red: 243/255, green: 246/255, blue: 250/255)
    static let card   = Color.white
    static let border = Color(red: 230/255, green: 235/255, blue: 241/255)
    static let blue   = Color(red: 47/255, green: 111/255, blue: 181/255)
    static let green  = Color(red: 47/255, green: 158/255, blue: 104/255)
    static let red    = Color(red: 214/255, green: 69/255, blue: 69/255)
    static let amber  = Color(red: 217/255, green: 131/255, blue: 36/255)
    static let txt    = Color(red: 26/255, green: 30/255, blue: 36/255)
    static let muted  = Color(red: 123/255, green: 133/255, blue: 146/255)
    static let faint  = Color(red: 152/255, green: 162/255, blue: 175/255)
}

// MARK: - 卡片容器
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(C.border, lineWidth: 1))
    }
}

// MARK: - 主界面
struct CarHomeView: View {
    @State private var st: CarState = CarState()
    @State private var loading = true
    @State private var toast: String?
    @State private var showLogin = false
    @State private var showPinSheet = false
    @State private var pinInput = ""
    @State private var resultTitle = ""
    @State private var resultMsg = ""
    @State private var showResult = false

    private let api = CarAPI.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    headerCard
                    if !api.isLoggedIn { loginPrompt }
                    statusCard
                    doorCard
                    quickRow
                    controlGrid
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .background(C.bg.ignoresSafeArea())
            .navigationTitle("车控")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { refresh() } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(C.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            pinInput = CarAPI.shared.controlPin
                            showPinSheet = true
                        } label: {
                            Label("设置控车码", systemImage: "lock.shield")
                        }
                        Button {
                            showLogin = true
                        } label: {
                            Label("重新登录", systemImage: "person.badge.key")
                        }
                        Divider()
                        Button(role: .destructive) {
                            logout()
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundColor(C.blue)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(C.txt.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.bottom, 30)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if !api.isLoggedIn {
                showLogin = true
            } else {
                refresh()
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView {
                showLogin = false
                refresh()
            }
        }
        .sheet(isPresented: $showPinSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("控车码")
                    .font(.system(size: 17, weight: .semibold))
                Text("长安 App 里设置的 6 位安全码，控车指令要用它做 RSA 加密")
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
                    toast = "控车码已保存"
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
            .presentationDetents([.height(280)])
        }
        .alert(resultTitle, isPresented: $showResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(resultMsg)
        }
    }

    private func logout() {
        CarAPI.shared.accessToken = ""
        CarAPI.shared.refreshToken = ""
        CarAPI.shared.carId = ""
        CarAPI.shared.controlPin = ""
        st = CarState()
        toast = "已退出登录"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showLogin = true
        }
    }

    // MARK: 顶部车名
    private var headerCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(st.carName.isEmpty ? "我的爱车" : st.carName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(C.txt)
                HStack(spacing: 6) {
                    Circle()
                        .fill(st.online ? C.green : C.faint)
                        .frame(width: 6, height: 6)
                    Text(st.online ? "在线" : "离线")
                        .font(.system(size: 11.5))
                        .foregroundColor(C.muted)
                    if !st.terminalTime.isEmpty {
                        Text("· \(String(st.terminalTime.suffix(8)))")
                            .font(.system(size: 11))
                            .foregroundColor(C.faint)
                    }
                }
            }
            Spacer()
            Image(systemName: "car.side.fill")
                .font(.system(size: 34))
                .foregroundColor(C.blue.opacity(0.85))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [C.blue.opacity(0.10), C.blue.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var loginPrompt: some View {
        Button {
            showLogin = true
        } label: {
            HStack {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                Text("未登录，点此登录长安账号")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(C.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: 车况
    private var statusCard: some View {
        Card {
            VStack(spacing: 12) {
                if loading {
                    ProgressView().padding(.vertical, 20)
                } else {
                    // 油量 + 续航
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("油量")
                                .font(.system(size: 11)).foregroundColor(C.faint)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(st.fuel.isEmpty ? "--" : st.fuel)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(C.txt)
                                Text("L").font(.system(size: 12)).foregroundColor(C.muted)
                                Text("· \(st.fuelPct)%")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(C.blue)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("续航")
                                .font(.system(size: 11)).foregroundColor(C.faint)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(st.range.isEmpty ? "--" : st.range)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(C.txt)
                                Text("km").font(.system(size: 12)).foregroundColor(C.muted)
                            }
                        }
                    }
                    // 进度条
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(C.bg)
                            Capsule().fill(C.blue)
                                .frame(width: g.size.width * CGFloat(min(100, max(0, st.fuelPct))) / 100)
                        }
                    }
                    .frame(height: 6)

                    Divider().opacity(0.5)

                    // 三个指标
                    HStack(spacing: 0) {
                        metric("总里程", st.odometer, "km")
                        Divider().frame(height: 26).opacity(0.5)
                        metric("电压", st.voltage, "V")
                        Divider().frame(height: 26).opacity(0.5)
                        metric("外温", st.outTemp, "°C")
                    }
                    // 胎压
                    HStack(spacing: 8) {
                        tyre("左前", st.lf)
                        tyre("右前", st.rf)
                        tyre("左后", st.lr)
                        tyre("右后", st.rr)
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            Text(value.isEmpty ? "--" : value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(C.txt)
            Text(title).font(.system(size: 10)).foregroundColor(C.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private func tyre(_ pos: String, _ v: String) -> some View {
        let n = Double(v) ?? 0
        let warn = n > 0 && (n < 200 || n > 280)
        return VStack(spacing: 2) {
            Text(v.isEmpty ? "--" : v)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(warn ? C.red : C.txt)
            Text(pos).font(.system(size: 9)).foregroundColor(C.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(warn ? C.red.opacity(0.07) : C.bg)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: 门窗
    private var doorCard: some View {
        Card {
            VStack(spacing: 10) {
                HStack {
                    Text("门窗")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.blue)
                    Spacer()
                    if st.anyOpen {
                        Button {
                            cmd("CloseWindow", "正在关闭车窗…")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.compress.vertical")
                                    .font(.system(size: 10, weight: .bold))
                                Text("一键关闭").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(C.blue)
                            .clipShape(Capsule())
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("全部关闭").font(.system(size: 10.5))
                        }
                        .foregroundColor(C.green)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    doorCell("主驾", st.doorFL, st.lockFL)
                    doorCell("副驾", st.doorFR, st.lockFR)
                    doorCell("左后", st.doorRL, st.lockRL)
                    doorCell("右后", st.doorRR, st.lockRR)
                    plainCell("后备箱", st.trunk, "shippingbox")
                    plainCell("引擎盖", st.hood, "engine.combustion")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 6) {
                    winCell("主驾窗", st.winFL)
                    winCell("副驾窗", st.winFR)
                    winCell("左后窗", st.winRL)
                    winCell("右后窗", st.winRR)
                }
            }
        }
    }

    private func doorCell(_ name: String, _ open: Bool, _ locked: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: open ? "door.left.hand.open" : "door.left.hand.closed")
                .font(.system(size: 19))
                .foregroundColor(open ? C.red : C.blue)
            HStack(spacing: 3) {
                Text(name).font(.system(size: 10.5)).foregroundColor(C.muted)
                Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 8))
                    .foregroundColor(locked ? C.green : C.amber)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(open ? C.red.opacity(0.07) : C.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func plainCell(_ name: String, _ open: Bool, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundColor(open ? C.red : C.blue)
            Text(name).font(.system(size: 10.5)).foregroundColor(C.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(open ? C.red.opacity(0.07) : C.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func winCell(_ name: String, _ open: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 15))
                .foregroundColor(open ? C.red : C.faint)
            Text(name).font(.system(size: 10.5)).foregroundColor(C.muted)
            Spacer()
            Text(open ? "开" : "关")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(open ? C.red : C.faint)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(open ? C.red.opacity(0.06) : C.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 快捷行
    private var quickRow: some View {
        HStack(spacing: 8) {
            quickBtn("开锁", "lock.open", "UnLockDoor")
            quickBtn("闭锁", "lock.fill", "LockDoor")
            quickBtn("闪灯", "lightbulb", "FlashLight")
            quickBtn("鸣笛", "speaker.wave.2.fill", "Whistle")
        }
    }

    private func quickBtn(_ title: String, _ icon: String, _ cmdName: String) -> some View {
        Button {
            cmd(cmdName, "正在\(title)…")
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.system(size: 10.5))
            }
            .foregroundColor(C.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(C.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(C.border, lineWidth: 1))
        }
    }

    // MARK: 控车九宫格
    private var controlGrid: some View {
        Card {
            VStack(spacing: 10) {
                HStack {
                    Text("车辆控制")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.blue)
                    Spacer()
                    Text("按住确认后下发")
                        .font(.system(size: 10)).foregroundColor(C.faint)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ctl("启动", "power", "OpenEngine")
                    ctl("熄火", "power.circle", "CloseEngine")
                    ctl("开空调", "snowflake", "openair")
                    ctl("关空调", "wind", "closeair")
                    ctl("升窗", "arrow.up.square", "CloseWindow")
                    ctl("降窗", "arrow.down.square", "OpenWindow")
                    ctl("留缝", "rectangle.split.3x1", "VentWindow")
                    ctl("开天窗", "sun.max", "OpenSunroof")
                    ctl("寻车", "location.magnifyingglass", "RemoteSearchCar")
                }
            }
        }
    }

    private func ctl(_ title: String, _ icon: String, _ cmdName: String) -> some View {
        Button {
            cmd(cmdName, "正在\(title)…")
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                Text(title).font(.system(size: 10.5))
            }
            .foregroundColor(C.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(C.bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: 动作
    private func refresh() {
        loading = true
        api.refreshIfNeeded { ok in
            guard ok else { loading = false; return }
            api.carData { d in
                DispatchQueue.main.async {
                    if let d = d { st = CarState(d) }
                    loading = false
                }
            }
        }
    }

    private func cmd(_ name: String, _ hint: String) {
        // 没有控车码先拦下来，直接引导设置
        if CarAPI.shared.controlPin.isEmpty {
            resultTitle = "缺少控车码"
            resultMsg = "控车指令要用控车码做 RSA 加密。\n请先到长安 App 确认 6 位安全码，再点右上角「设置控车码」。"
            showResult = true
            return
        }
        toast = hint
        api.control(cmd: name) { ok, msg in
            DispatchQueue.main.async {
                toast = nil
                resultTitle = ok ? "已下发" : "下发失败"
                resultMsg = msg.isEmpty ? (ok ? "指令已发出，稍等几秒刷新看状态" : "未知错误") : msg
                showResult = true
                if ok {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refresh() }
                }
            }
        }
    }
}

// MARK: - 车况数据模型
struct CarState {
    var carName = ""
    var online = false
    var terminalTime = ""
    var fuel = ""
    var fuelPct = 0
    var range = ""
    var odometer = ""
    var voltage = ""
    var outTemp = ""
    var lf = "", rf = "", lr = "", rr = ""
    var doorFL = false, doorFR = false, doorRL = false, doorRR = false
    var lockFL = true, lockFR = true, lockRL = true, lockRR = true
    var trunk = false, hood = false
    var winFL = false, winFR = false, winRL = false, winRR = false

    init() {}

    init(_ d: [String: Any]) {
        func s(_ k: String) -> String {
            if let v = d[k] as? String { return v }
            if let v = d[k] as? Int { return "\(v)" }
            if let v = d[k] as? Double { return String(format: "%.1f", v) }
            return ""
        }
        func b(_ k: String) -> Bool { (d[k] as? Int) == 1 }
        func b0(_ k: String) -> Bool { (d[k] as? Int) == 0 }   // 锁：0=已锁

        fuel = s("fuelLeftover")
        let f = Double(fuel) ?? 0
        fuelPct = Int(round(f / 53 * 100))
        range = s("remainedOilMile")
        odometer = s("totalOdometer")
        voltage = s("batteryVoltage")
        outTemp = s("environmentalTemp")
        lf = s("lfTyrePressure"); rf = s("rfTyrePressure")
        lr = s("lrTyrePressure"); rr = s("rrTyrePressure")

        doorFL = b("leftFrontDoor");  doorFR = b("rightFrontDoor")
        doorRL = b("leftRearDoor");   doorRR = b("rightRearDoor")
        lockFL = b0("leftFrontDoorLock");  lockFR = b0("rightFrontDoorLock")
        lockRL = b0("leftRearDoorLock");   lockRR = b0("rightRearDoorLock")
        trunk = b("trunk"); hood = b("hood")
        winFL = b("leftFrontDoorrWindow"); winFR = b("rightFrontDoorrWindow")
        winRL = b("leftRearWindow");       winRR = b("rightRearWindow")

        terminalTime = s("terminalTime")
        online = !terminalTime.isEmpty
    }

    var anyOpen: Bool { doorFL || doorFR || doorRL || doorRR || winFL || winFR || winRL || winRR }
}
