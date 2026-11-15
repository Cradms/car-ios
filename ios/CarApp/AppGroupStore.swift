import Foundation

/// 主 App → 小组件 共享状态
enum AppGroupStore {
    static let group = "group.com.yg.carapp"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: group) ?? .standard
    }

    static func set(_ v: String, _ k: String) { defaults.set(v, forKey: k) }

    /// 车况同步给小组件
    static func sync(_ s: CarState) {
        set(s.fuel, "w_fuel")
        set(s.range, "w_range")
        set(s.odometer, "w_odo")
        set(s.voltage, "w_voltage")
        set(s.outTemp, "w_out")
        set(s.lf, "w_lf"); set(s.rf, "w_rf")
        set(s.lr, "w_lr"); set(s.rr, "w_rr")
        set(s.carName.isEmpty ? "我的爱车" : s.carName, "w_car")
        set(s.online ? "1" : "0", "w_online")
        set(s.anyOpen ? "1" : "0", "w_open")
        set((s.lockFL && s.lockFR && s.lockRL && s.lockRR) ? "1" : "0", "w_locked")
        defaults.set(Date().timeIntervalSince1970, forKey: "w_at")
    }

    /// 凭证同步（小组件发指令要用）
    static func syncCredentials() {
        let api = CarAPI.shared
        set(api.accessToken, "w_token")
        set(api.refreshToken, "w_rt")
        set(api.carId, "w_cid")
        set(api.controlPin, "w_pin")
    }
}
