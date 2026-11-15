# 长安车控 iOS（按 4.5.6 小组件版源码复刻）

纯 SwiftUI 原生工程，不依赖自建服务器、不使用 WebView。数据层按 Android 端
**长安车控 4.5.6（vc114）小组件版** 的 `java/com/xiaoan/cac/*.java` 逐条复刻。

- 主 App：车况 / 控车 / 位置 / 轨迹 / 记录 / 保养 / 消息
- 小组件（WidgetKit）：按车型显示车模图 + 续航 + 门锁状态 + 快捷控车深链

## 接口通道（与源码 Api.java 一致）

| 通道 | 域名 | 用途 |
| --- | --- | --- |
| 老通道 | `m.iov.changan.com.cn` | 短信登录、车况、控车、轨迹、记录、全景照片 |
| 开放平台 | `open.iov.changan.com.cn` | 扫码 OAuth 登录、车型信息、VCS-HMAC-SHA256 签名接口 |
| 续期 | `incallapi.changan.com.cn` | `refresh_token` 换新令牌 |

签名算法（`CarAPI.vcsAuth`）：

```
canonical = METHOD \n path \n urlencode(k=v&...) \n  sorted("k:v\n") \n sha256(body)
Authorization: VCS-HMAC-SHA256 Signature=hmac_sha256(secretKey,
               "VCS-HMAC-SHA256\n{ts}\n sha256(canonical)")
```

控车链路（`CarAPI.miControl`）：`createPinVerifyCode` → `v2/security/key` 取公钥
（SPKI，拆 BIT STRING 转 PKCS#1）→ `RSA/ECB/OAEPWithSHA-256AndMGF1Padding` 加密
`{pinVerifyCode,cmd,type,pin,wifiPassword}` → `v3/control/execute` → `getControlInfo` 轮询。

## 车型归一化

`CarModel.normalize` 与源码 `CarModelImage.normalize` 一致：车名/车架号 → 车型代码，
代码再映射车模图与中文名。小组件也内置同一份映射（Widget target 不引用 App 代码）。

| 代码 | 车型 | 代码 | 车型 |
| --- | --- | --- | --- |
| C211 | 逸动 PLUS | S202 | UNI-T |
| C236 | 启源 A07 | S203 | CS55 Plus |
| C281 | UNI-V | S203_P | 启源 Q05 |
| C281_P | 启源 A06 | S311 | CS75 Plus 二代 |
| C589 | 逸达 / 逸动 | S311_P | CS75 Plus 三代 |
| C589_P | 启源 A05 | S311MCA | CS75 Plus 四代 |
| CD569 | UNI-K | — | — |

小组件优先用 `seriesName` 归一化，拿不到再退回 `seriesCode`，最后用通用图 `car`。

## 目录

```
ios/
├── project.yml                 XcodeGen 工程定义（App + Widget，未签名可编）
├── CarApp/
│   ├── CarAPI.swift            接口层（登录/车况/控车/轨迹/记录/照片）
│   ├── CarModel.swift          车型归一化 + 名称映射
│   ├── AppGroupStore.swift     App → Widget 共享状态
│   ├── RSACrypto.swift         RSA-OAEP(SHA256)，SPKI→PKCS#1
│   ├── CarHomeView.swift       首页（车模图 / 车况 / 门窗 / 控车九宫格）
│   ├── LoginView.swift         短信验证码 + 控车码
│   ├── LocationView.swift      车辆位置与导航
│   ├── TrackView / HistoryView / PhotoView  （ExtraViews.swift）
│   ├── FuelView / MaintainView / MoreView
│   ├── RootView / AppDelegate  5 个 Tab + carapp:// 深链
│   └── Assets.xcassets         13 张车型图 + 通用车模图
└── CarWidget/                  WidgetKit 小组件（同名车型图副本）
```

## 编译（自己出 IPA）

```bash
brew install xcodegen
cd ios && xcodegen generate
open CarApp.xcodeproj
```

Xcode 里选自己的开发者账号 → 真机运行，或 `Product > Archive` 导出 IPA。
工程默认 `CODE_SIGNING_ALLOWED=NO`，需要签名时在 Xcode 里放开即可。

命令行出未签名 IPA：

```bash
cd ios && xcodegen generate
xcodebuild -project CarApp.xcodeproj -scheme CarApp -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/CarApp.app Payload/
zip -qry CarApp-unsigned.ipa Payload
```

再自签（AltStore / Sideloadly / TrollStore / 自签证书）安装。

GitHub Actions（`.github/workflows/ios-build.yml`）会在 push 时跑 macOS runner：
未配置证书 → 产出未签名 IPA；配置 `P12_BASE64 / P12_PASSWORD / PROFILE_BASE64 / TEAM_ID` → 签名 IPA。

## 登录与控车码

- 短信登录：`/api/sms/sendAuthcode` → `/app2/api/oauth2login/token/stageOne`（拿 m.iov 令牌）
- 扫码登录：`/oauth/api/qrcode/generate` → 轮询 `getQrcodeStatusNoBackend` → `/oauth/token`
  （拿开放平台 `access_token` + `secret_key`，车型/开放接口需要它）
- 控车码：长安 App 里的 6 位安全码，用 RSA 公钥加密后随指令下发，存本地

## 已知限制

- 蓝牙钥匙（`BleKeyClient.java`，26KB BLE GATT 协议）**未移植**：iOS 侧需要车端密约与
  实车抓包，仓库里没有对应实现，首页只保留联网控车。
- 里程/电压/油量字段老版本接口才有，4.5.6 车况只稳定返回续航与门窗锁状态，界面按
  拿到的字段显示，空值显示 `--`。
- 未在实车验证过的接口按源码原样实现，返回结构有兜底解析（多种字段名 + 多层 data 包裹）。
