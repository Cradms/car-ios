import UIKit
import SwiftUI

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: RootView())
        window.makeKeyAndVisible()
        self.window = window

        // 冷启动时由小组件深链拉起的指令
        if let url = launchOptions?[.url] as? URL {
            _ = handle(url)
        }
        return true
    }

    /// 小组件快捷按钮：carapp://action?cmd=LockDoor
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        handle(url)
    }

    @discardableResult
    private func handle(_ url: URL) -> Bool {
        guard url.scheme == "carapp" else { return false }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let cmd = comps?.queryItems?.first(where: { $0.name == "cmd" })?.value,
              !cmd.isEmpty else { return true }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = CarAPI.shared.execute(cmd)
            _ = CarAPI.shared.fetchStatus()
            AppGroupStore.syncFromPrefs()
        }
        return true
    }
}
