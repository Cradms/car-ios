# 车控 iOS App（原生直连版）

**不依赖自建服务器**，App 内部直接调长安接口。UI 复用现有 H5 页面（打包进 App），数据层全部是原生 Swift。

## 架构

```
App
├── WebViewController       加载 carapp://local/index.html（包内页面）
├── LocalSchemeHandler      拦截 carapp://local/api/*  →  转发原生
├── CarAPI                  URLSession 直连 m.iov.changan.com.cn
├── RSACrypto               RSA-OAEP(SHA256) 加密控车指令
├── LoginViewController     手机号 + 短信验证码 + 控车码
└── Resources/site/         打包进 App 的 H5 页面（121 个文件，13MB）
```

H5 里原来的 `fetch('/api/real/cardata')` 会自动变成 `carapp://local/api/real/cardata`，
被 `LocalSchemeHandler` 拦下来交给原生处理。**页面代码一行没改。**

## 已实现的接口

| H5 请求 | 原生实现 |
| --- | --- |
| `/api/real/session` | 检查 Keychain 里的登录态 |
| `/api/real/sms` | `POST /api/sms/sendAuthcode` |
| `/api/real/login` | `POST /app2/api/oauth2login/token/stageOne` |
| `/api/real/cardata` | `POST /app2/api/car/data` |
| `/api/real/location` | `GET /app2/api/car/location` |
| `/api/real/energy` | `GET /app2/api/car-report/car-energy-trend` |
| `/api/real/maintenance` | `GET /mt/uc/api/maintenance/next` + `/history` |
| `/api/real/control` | 取 pinVerifyCode → 取公钥 → RSA 加密 → `v3/control/execute` |
| `/api/oil/price` | `api.qqsuu.cn` 当日油价 |

其余接口（油耗记账、告警配置等）目前返回空成功，页面不会报错，只是没数据。

## 登录流程

App 首次启动 → 弹出原生登录页：

```
手机号  [ 11 位        ]
验证码  [ 6 位 ] [获取验证码]     ← 60 秒倒计时
控车码  [ 6 位 ····   ]           ← 长安 App 里设置的那个
        [ 登录 ]
```

登录成功后 token 存 Keychain，车名/车牌自动拉取，之后直接进主页。
token 过期会自动用 refresh_token 换新的，不用重新登录。

## 编译

### GitHub Actions（推荐，不用 Mac）

```bash
GH_USER=你的用户名 GH_TOKEN=你的token ./push-github.sh
```

推上去后进 Actions 页签，`Build unsigned IPA` 会自动跑（约 3~5 分钟），
产物在 run 详情页底部 `Artifacts` → `CarApp-unsigned-ipa`。

### 本地 Mac

```bash
python build.py          # 先生成 site/
./ios/sync_site.sh       # 同步页面进 App 资源
brew install xcodegen
cd ios && xcodegen generate && open CarApp.xcodeproj
```

Xcode 里选账号 → 连手机 → Run，或 `Product > Archive` 导出 ipa。

## 签名

| 工具 | 说明 |
| --- | --- |
| Sideloadly / AltStore | Apple ID 免费签，7 天 |
| TrollStore | A12~A15 + iOS 14~16.6.5，永久 |
| 企业签 | 买证书，不掉签 |

## 改 Bundle ID

`ios/project.yml`：

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.yg.carapp
```

换成你自己的，避免和别人的证书冲突。

## 注意

- **控车码必须填对**：控车指令要用它做 RSA 加密的 pin 字段，错了会被长安拒绝
- **首次登录要短信验证码**：和车机 App 同一账号
- **页面改了要重新同步**：改完 H5 跑一次 `./ios/sync_site.sh`
- **推送仍是 Bark**：这个 App 没有接 APNs，通知走 Bark App
