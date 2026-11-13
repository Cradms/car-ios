# 车控 iOS App（WKWebView 壳）

把服务器上的页面装成 iPhone 桌面 App。Swift + WKWebView，无第三方依赖。

## 一、先改服务器地址

打开 `ios/CarApp/Info.plist`，找到：

```xml
<key>ServerURL</key>
<string>http://192.168.123.72:8088</string>
```

这里默认是**局域网地址**，只有手机连同一个 WiFi 才能访问。要出门也能用，换成你的公网地址（内网穿透 / DDNS / 云服务器），例如：

```xml
<string>https://car.yourdomain.com</string>
```

> 用 https 的话，`NSAppTransportSecurity` 那一段可以删掉。

## 二、生成 IPA（三种方式，任选）

### 方式 A：GitHub Actions（不用 Mac）

1. 把整个 `replica` 目录推到一个 GitHub 仓库
2. 仓库的 `Actions` 页签会看到 `Build unsigned IPA`，点 `Run workflow`
3. 等 3~5 分钟，进这次运行，底部 `Artifacts` 下载 `CarApp-unsigned-ipa`
4. 解压得到 `CarApp-unsigned.ipa`

工作流已经配好（`.github/workflows/ios-build.yml`），自动装 XcodeGen、生成工程、编译、打包 IPA。

### 方式 B：Mac + Xcode（有 Mac 最快）

```bash
brew install xcodegen
cd ios
xcodegen generate
open CarApp.xcodeproj
```

Xcode 里选你的开发者账号 → 连接 iPhone → Run。
要导出 IPA：`Product > Archive > Distribute App > Custom > 导出 .ipa`。

### 方式 C：在线打包

搜索「iOS 在线打包 / 云端编译」，上传源码 zip，选 Xcode 版本，它会返回 ipa。适合没有 Mac 也不想用 GitHub 的情况。

## 三、签名安装

拿到未签名 ipa 后，用你手上的工具签名：

| 工具 | 适用 |
| --- | --- |
| **Sideloadly** | Windows/Mac，用 Apple ID 免费签，7 天有效期 |
| **AltStore** | 同上，自动续签 |
| **TrollStore** | 仅限 A12~A15 + iOS 14~16.6.1，永久免签 |
| **企业签 / 超级签** | 买证书，装完不掉签 |
| **Xcode 直接 Run** | 有 Mac 时最省事，免费账号 7 天 |

免费账号签的 App 每 7 天要重签一次；付费开发者账号（$99/年）签的是 1 年。

## 四、这个壳做了什么

| 能力 | 说明 |
| --- | --- |
| 全屏 WebView | 无地址栏，像原生 App |
| 下拉刷新 | 顶部下拉重新加载 |
| 加载时间戳 | 每次启动带 `?t=时间戳`，避免缓存旧页面 |
| 弹窗兼容 | `alert / confirm / prompt` 自动转原生弹窗 |
| 外链处理 | 非本站域名（高德导航、支付）自动跳系统浏览器 |
| 定位授权 | 请求 `WhenInUse`，页面地图可读当前位置 |
| 相机/相册 | 已配权限说明，页面 `<input type=file>` 可用 |
| 原生桥 | `window.webkit.messageHandlers.native.postMessage("refresh")` 可触发刷新 |

## 五、改 Bundle ID

`ios/project.yml`：

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.yg.carapp
```

改成你自己的（比如 `com.你的名字.carapp`），否则和别人的签名证书可能冲突。

## 六、已知限制

- **页面依赖服务器**：App 只是壳，服务器挂了页面就白屏。要离线用，得把后端也搬进 App（Python 跑不了，需要 Node/Go 重写并内嵌）。
- **推送**：Bark 推送走的是 Bark App，不受影响；但这个壳本身没有 APNs 能力，要原生推送得加推送证书和 `UNUserNotificationCenter`。
- **后台保活**：iOS 限制，App 退到后台会被挂起，需要后台任务得申请 `BGTaskScheduler`。

## 七、文件清单

```
ios/
├── project.yml                    # XcodeGen 配置
├── CarApp/
│   ├── AppDelegate.swift          # 启动
│   ├── WebViewController.swift    # WebView 主体
│   ├── Info.plist                 # 地址 / 权限 / ATS
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/
│           └── icon-1024.png      # 图标（可换）
.github/workflows/ios-build.yml    # 自动编译 IPA
```
