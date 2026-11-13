# 已部署实例记录

## 访问地址

```
http://192.168.123.72:8088
```

| 项 | 值 |
| --- | --- |
| 手机号 | `13800138000` |
| 控车码 | `123456` |
| 管理密码 | `umeko-h908b0` |

> 管理密码用于「我的 → 管理员管理」和「使用统计与管理」。改密码见文末。

## 运行方式：Docker 容器

| 项 | 值 |
| --- | --- |
| 主机 | `192.168.123.72`（aarch64，Ubuntu 24.04，Docker 29.9.3 + compose v5.7） |
| 账号 | `umeko`（sudo 可用；不在 docker 组，故命令都要 `sudo`） |
| 项目目录 | `/home/umeko/car-replica`（`server.py` + `site/` + `Dockerfile` + `docker-compose.yml` + `.env`） |
| 镜像 | `car-replica:latest`，基于 `docker.1ms.run/library/python:3.12-alpine` |
| 容器 | `car-replica`，`Up`，端口映射 `0.0.0.0:8088 -> 8080` |
| 重启策略 | `unless-stopped`；Docker 服务已 `enabled`，开机自动拉起容器 |
| 数据 | 宿主机 `/home/umeko/car-replica/data/data.json`，挂载到容器 `/data` |
| 请求日志 | `/home/umeko/car-replica/data/requests.log` |

## 常用命令

```bash
cd /home/umeko/car-replica

sudo docker compose ps                       # 状态
sudo docker compose logs -f --tail=50        # 日志
sudo docker compose restart                  # 重启
sudo docker compose down                     # 停止
sudo docker compose up -d                    # 启动
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8088/   # 健康检查

# 备份数据
cp data/data.json data/data-$(date +%F).json

# 改管理密码
sudo docker compose down
sudo sed -i 's/^ADMIN_PASS=.*/ADMIN_PASS=新密码/' .env
mv data/data.json data/data.json.bak          # 密码哈希存在数据里，需重建
sudo docker compose up -d
```

## 更新程序

本地改完 → 重新打包上传 → 重启容器：

```bash
cd replica && python build.py && tar -czf _dist.tgz -C _dist .
scp _dist.tgz umeko@192.168.123.72:/home/umeko/car-replica/
ssh umeko@192.168.123.72 'cd ~/car-replica && tar -xzf _dist.tgz && rm _dist.tgz && sudo docker compose up -d --build'
```

注意：`_dist.tgz` 里只含 `site/`、`server.py`、`Dockerfile`、`docker-compose.yml`，解包不会覆盖 `data/` 目录，数据安全。

## 备选：不用 Docker 的原生方式

我最初因为镜像拉不下来，先用系统 Python 跑过一版（`car-replica.service`，已 `disable`，unit 文件还在 `/etc/systemd/system/`）。必要时可切回：

```bash
sudo docker compose down
sudo systemctl enable --now car-replica     # 它监听同样的 8088
```

两套互斥，不要同时开（会抢 8088）。

## 部署过程记录（踩过的坑）

1. 这台机器直连 `registry-1.docker.io` 不通（返回 000），必须走镜像源 `docker.1ms.run`
2. 拉 `python:3.12-slim` 时层下载完长期卡在 `Waiting`，累计 20+ 分钟未完成；换更小的 `python:3.12-alpine` 后，最终约 20 分钟拉完
3. `umeko` 不在 docker 组，所有 docker 命令都要 `sudo`（密码 1234）
4. `sudo mkdir` 建立的目录属主是 root，`umeko` 写不进去 → 必须 `chown -R umeko:umeko`

## 已验证

- `http://192.168.123.72:8088/` → 200（局域网 17ms）
- 登录 `13800138000 / 123456` → 进入控车页
- 3D 车模 canvas 渲染正常（590×252）
- 五个 Tab（控车/车况/圈子/油耗/我的）全部可切换
- 全站无 4xx/5xx，无 JS 报错
- 管理接口：不带密码 → `{"wrong_pass":true}` 无数据；带密码 → 200
- 原 `data.json` 已迁移进容器挂载目录，历史使用记录保留（`need_init:false`）

## 真实车辆接入（已就绪）

访问 `http://192.168.123.72:8088/real`，填「手机号 + 控车码 + refresh_token」，保存后自动进入真实模式。

技术链路：

| 环节 | 实现 | 验证结果 |
| --- | --- | --- |
| 浏览器 → 长安接口 | `replica_shim.js` 把 `m.iov/incallapi/open.iov/高德` 改写到 `/real/*` | 已生效 |
| 服务端转发 | `server.py::proxy_real()` 转发到真实域名，补齐 `okhttp/4.9.0`、`vcs-app-id: inCall` 等头 | 实测上游返回 `{"code":2,"msg":"token已过期"}`，说明已打通 |
| 控车加密 | `rsa_enc.py` 纯标准库 RSA/PKCS#1 v1.5（DER 解析 + 模幂） | 用 openssl 生成的密钥对加解密对拍通过 |
| 水印 | 真实模式下自动隐藏「模拟数据」水印 | 已生效 |

还缺的一步：一个**有效的 refresh_token**（属于你自己已开通车联网的长安账号）。

获取方式：手机装「长安汽车」App 登录 → 用 Reqable / HttpCanary 抓 `incallapi.changan.com.cn` → 找 `oauth2/refresh_token` 请求 → 复制 `refresh_token=` 后的值。

注意：refresh_token 会随使用轮换（响应里会下发新的），过期后需重新粘贴；后续可加自动轮换落库。

## 真实车联网打通（v2，已上线）

入口：`http://192.168.123.72:8088` → 登录页红按钮「用车联网账号登录 · 真实控车」→ `/real`

### 链路（全部实测通过）

| 环节 | 接口 | 关键参数 |
| --- | --- | --- |
| 发码 | `POST m.iov.changan.com.cn/api/sms/sendAuthcode` | form: `phone=` |
| 验证码登录 | `POST m.iov.changan.com.cn/app2/api/oauth2login/token/stageOne` | form: `mobile=` + `vercode=` |
| 续期 | `GET incallapi.changan.com.cn/cac/api/v1/oauth2/refresh_token` | `client_id=2c918082632162010163388048d60158&refresh_token=` |
| 车辆 | `GET m.iov.../app2/api/user/cars?type=0&token=` | — |
| 车况 | `POST m.iov.../app2/api/car/data?carId=&keys=*&isNev=0&token=` | 必须 POST |
| 控车公钥 | `GET m.iov.../app2/api/v2/security/key?carId=&token=` | RSA-2048 |
| 控车 | `POST m.iov.../app2/api/v3/control/execute` | form: `carId,token,isNev=0,s=<RSA密文>` |

请求头固定：`Accept: */*` + `User-Agent: ChanganInCall/5.2.0 (iPhone; iOS 15.0; Scale/3.00)` + `X-Requested-With: cn.com.changan.cvim`，**无需任何签名**。

控车明文：`{"cmd":"LockDoor","type":"LockDoor","pin":"******","pinVerifyCode":"xxx"}`（PIN 前先取 `createPinVerifyCode`），RSA/PKCS#1 加密后放 `s`。

### 新增服务端接口

- `POST /api/real/sms` `{phone}` → 下官方短信验证码
- `POST /api/real/login` `{phone,code,pin}` → 换 token + 落库 + 返回真实车名/车牌
- `/real/iov/m|incall|open`、`/real/amap` 同源代理（已存在）

### 实测数据（真车）

UNI-V 尊贵型 2022款，川QQQ318，VIN LS5A2DKE8NA309244，里程 54820.9 km，油量 44L/53L，胎压 237/240/237/238，车联网 active。

### 注意

- access_token 有效期 3600s；refresh_token 可续期（已实测换出新 token），前端 `getOpenAuthorizeToken()` 会用 ref_token 自动换。
- 控车必须输对控车码（长安引力域 App 里设置的 6 位 PIN），服务端只做转发与 RSA 加密，不存储明文 PIN。
