# 远程控车系统 · 本地复刻版

## 快速开始

```bash
python build.py        # 首次或改动 _dump/ 后执行，组装 site/
python server.py 8080  # 启动
# 打开 http://127.0.0.1:8080
```

Windows 直接双击 `start.bat`。需要 Python 3.8+，无第三方依赖。

## 演示账号

| 用途 | 值 |
| --- | --- |
| 手机号 | `13800138000` |
| 控车码（PIN） | `123456` |
| 管理密码 | `admin888` |

卡密系统已**整套物理删除**（不是隐藏）：前端不再有卡密弹窗、卡密生成/列表/作废/删除、体验卡与永久卡、体验模式限制、体验版角标；后端不再有 `/api/card/*`、`/admin/card/*` 与 `cards` 数据。登录即全功能。

登录页另可用「短信登录」：验证码为模拟下发，随便填或填 `123456` 均可通过。

## 目录结构

```
replica/
├── _dump/            抓取到的原始资源（未改动，作为还原基线）
├── site/             build.py 组装出的可运行站点（改动会被覆盖）
├── replica_shim.js   运行层：把第三方域名改写为本地 mock + 右下角复刻标识
├── build.py          组装 site/：拷贝、补丁、注入 shim
├── strip_card.py     卡密系统清理器（DOM + JS 物理删除，37 项操作）
├── server.py         复刻后端：静态托管 + 全接口模拟 + 数据落盘
├── mirror.py         抓站脚本（递归扒页面/静态资源）
├── check.py          Playwright 全流程验证脚本
├── data.json         运行时数据（删掉即重置为种子数据）
├── requests.log      接口调用日志（含 FALLBACK 标记）
└── shots/            验证截图
```

## 原站结构（扒站还原的结论）

前端是纯静态 + 浏览器直连三方接口的混合架构：

- **自有后端**（同源，负责业务）：`/get_user_info`、`/check_phone_exists`、`/get_code`、`/register_user`、`/save_token`、`/api/card/status`、`/api/card/verify`、`/api/auth/status`、`/api/auth/revoke`、`/api/usage/beat`、`/agent/*`、`/admin/*`（15 个）、`/myth/*`、`/api/siri/*`、`/api/club/*`、`/api/fuel/*`、`/encrypt_data`、`/get_scode`、`/api/ac/*`
- **长安官方 iov**（浏览器直连，需真实凭证）：`incallapi.changan.com.cn` 的 `oauth2/refresh_token`、`m.iov.changan.com.cn` 的 `user/cars`、`car/data`、`security/key`、`control/createPinVerifyCode`、`v3/control/execute`，以及 `open.iov.changan.com.cn`
- **高德**：`dualstack-arestapi.amap.com` 路况
- 卡密不是本地校验：前端拿到卡密后打 `/api/card/verify`，服务端写入账号授权，`/api/card/status` 回 `regular / permanent / today_ok` 决定体验版限制（体验版只剩「控车 + 车况」两个 Tab）

复刻版把上面三类三方调用统一改写到 `/mock/...`（`replica_shim.js` 改写 fetch/XHR，`server.py` 返回模拟数据），因此**离线可跑通登录 → 卡密 → 控车 → 车况 → 圈子 → 油耗 → 我的**全链路。

## 上线部署

完整步骤见 **`DEPLOY.md`**（云服务器 / Docker / 内网穿透三种方案）。要点：

- 服务默认监听 `0.0.0.0` 并打印局域网地址，同一 WiFi 手机可直接访问
- 生产环境必须设置 `ADMIN_PASS`、`DEMO_PIN`、`REPLICA_ENV=prod`
- `deploy/` 里已备好 `Dockerfile`、`docker-compose.yml`、`nginx.conf`、`replica.service`
- 数据只有 `data.json` 一个文件（`DATA_FILE` 可指定路径），挂卷即可持久化

### 内置安全措施

| 项 | 做法 |
| --- | --- |
| 控车码 / 管理密码存储 | PBKDF2-SHA256 + 随机盐，`data.json` 里不存明文 |
| 管理接口鉴权 | `/admin/*` 全部强制校验管理密码，失败返回 `wrong_pass` 且不回传任何数据 |
| 撞库防护 | 同一 IP 5 分钟内失败 8 次即熔断，返回 429 |
| 响应头 | `X-Content-Type-Options`、`X-Frame-Options: SAMEORIGIN`、`Referrer-Policy` |
| 区分探测与错误 | 前端会先用空密码探测初始化状态，空密码不计入失败次数 |

## 与原站的差异

0. **卡密系统已整套删除**（本版改动的重点，由 `strip_card.py` 在构建时物理移除，共 37 项）：
   - 前端：登录页卡密弹窗与校验（`openCardCheckOrGo` / `openCardModal` / `submitCard` / `backToLogin` / `PENDING`）、体验卡管理区与永久卡区、卡密生成/复制/作废/删除、`checkExperienceMode` 与 `_applyExpRestrictions` 体验模式限制、体验版角标与升级弹层、体验版 Tab 拦截、车况页的卡密校验 IIFE、用户明细里的「正式 / 体验 / 未授权」徽标
   - 后端：`/api/card/status`、`/api/card/verify`、`/admin/card/{list,generate,void,delete}` 六个端点，以及 `cards` 数据、`card_of()`、`r_card_verify()` 等全部实现
   - 保留：`永久卡` 弹层里的「管理员任命」被拆出来，改名成「管理员管理」入口（`我的` → 管理员管理，管理密码 `admin888`），管理员增删/改密照常可用
   - 保留了 0 处卡密残留：`site/` 四个文件扫描 `卡密 / permCard / EXP_MODE / 体验版 / 体验卡 / 永久卡 / api/card/ / admin/card/` 全部为 0
1. 三方接口（长安 iov / 高德）为本地模拟，返回固定车辆数据（逸动 PLUS，油量 41.2L、续航 486km、四轮胎压等），不会真正下发控车指令。
2. `vehicle_status.html` 有两处服务端渲染痕迹，已在 `build.py` 里打补丁：① 无参时无条件报「缺少必要参数」的占位块改成按真实参数判断；② 隐藏域凭证改为从 URL / localStorage 回填。
3. Google AdSense 脚本保留原样，离线时控制台会有一条 `ERR_NAME_NOT_RESOLVED`，不影响功能。
4. 未实现的少数接口走兜底返回 `{success:true}`，并在 `requests.log` 标记 `FALLBACK`，便于继续补。

## 验证结果

`python check.py` 在 430×932 移动端视口跑完整流程，结果：

- 登录页 → 控车页跳转正常，3D 车模（`EadoPlus2022.rk.json` + 5.8MB `.bin` + 9 张贴图）渲染成功
- 车况卡片、快捷按钮（闪灯 / 开锁 / 闭锁 / 鸣笛）、10 个控车按钮网格全部就位
- 控车按钮点击 → 弹出「普通锁车 / 一键锁车」→ 下发指令成功
- 全站文本与源码里「卡密 / 体验版 / 体验卡 / 永久卡」出现次数为 **0**
- 登录即进控车页，五个 Tab 全开；「我的 → 管理员管理」密码校验后可按任命/重置密码/卸任
- 五个 Tab 全部可切换；车况页 8 项自检全「正常」，四轮胎压、油耗记录（含区间油耗）正常显示
- 静态资源零 404，除广告脚本外无失败请求，无 JS 报错

截图见 `shots/`。
