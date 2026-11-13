# 上线部署指南

复刻版是**纯标准库 Python 服务**（无依赖、单进程、单端口），部署成本很低。三条路，按你的目的选：

| 方案 | 适合 | 成本 | 门槛 |
| --- | --- | --- | --- |
| A 云服务器 + Nginx | 长期给多人用，要自己的域名 | ¥50~100/月 | 需要会点 Linux；国内服务器绑域名要备案 |
| B Docker 一把梭 | 已有服务器/群晖/树莓派 | 同上 | 会装 Docker 就行 |
| C 家里电脑 + 内网穿透 | 自己用、先试水 | ¥0 起 | 电脑得常开 |

---

## 上线前必须做的三件事

```bash
# 1) 改管理密码（否则任何人拿到 admin888 就能看用户列表、踢人）
ADMIN_PASS='你的强密码'

# 2) 改演示账号的控车码（默认 123456 等于没锁）
DEMO_PIN='你的控车码'

# 3) 打开生产模式
REPLICA_ENV=prod
```

> 说明：密码在 `data.json` 里以 PBKDF2-SHA256 加盐哈希存储，`/admin/*` 全部接口强制校验管理密码，登录失败 8 次/5 分钟会被限流。这些是内置的，不用额外做。

---

## 方案 A：云服务器（推荐）

买一台 1 核 1G 的 Ubuntu 22.04/24.04（阿里云轻量、腾讯云轻量、Vultr、Hetzner 都行），然后：

```bash
# 1. 装依赖
sudo apt update && sudo apt install -y python3 nginx certbot python3-certbot-nginx

# 2. 传代码（本地执行）
scp -r replica root@你的服务器IP:/opt/car-replica

# 3. 组装站点（服务器上执行）
cd /opt/car-replica && sudo python3 build.py

# 4. 用 systemd 常驻
sudo cp deploy/replica.service /etc/systemd/system/car-replica.service
sudo nano /etc/systemd/system/car-replica.service   # 改 ADMIN_PASS
sudo systemctl daemon-reload
sudo systemctl enable --now car-replica
curl -I http://127.0.0.1:8080                     # 应返回 200

# 5. Nginx 反代 + 域名
sudo cp deploy/nginx.conf /etc/nginx/sites-available/car
sudo nano /etc/nginx/sites-available/car           # 改 server_name 为你的域名
sudo ln -s /etc/nginx/sites-available/car /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 6. 免费 HTTPS（自动续期）
sudo certbot --nginx -d car.example.com
```

域名解析：A 记录指向服务器 IP。**国内服务器必须先完成 ICP 备案**，否则 80/443 会被拦；不想备案就买香港/新加坡节点。

防火墙只放 22 / 80 / 443，8080 不要对外：

```bash
sudo ufw allow 22,80,443/tcp && sudo ufw enable
```

---

## 方案 B：Docker

服务器装好 Docker 后：

```bash
cd /path/to/replica/deploy
cp .env.example .env && nano .env          # 改 ADMIN_PASS / DEMO_PIN
docker compose up -d --build
docker compose logs -f                     # 看启动日志
curl -I http://127.0.0.1:8080
```

镜像里已经内置 `build.py` 组装 + 卡密清理，`data.json` 挂在 `deploy/data/`，重建容器数据不丢。前面同样建议挂 Nginx + certbot（照方案 A 第 5、6 步）。

升级：`git pull`（或覆盖代码）后 `docker compose up -d --build`。

---

## 方案 C：家里电脑 + 内网穿透（零成本试用）

```bash
# 本机启动（会自动监听 0.0.0.0 并打印局域网地址）
python server.py 8080

# Cloudflare Tunnel（免公网 IP、自带 HTTPS，免费）
cloudflared tunnel --url http://127.0.0.1:8080
# 输出一个 https://xxx.trycloudflare.com 的公网地址，手机随时能开
```

缺点：电脑关机就断；临时域名每次变。想固定域名就注册 Cloudflare 账号绑定自己的域名，或改用 frp 自建。

---

## 数据与备份

- 所有业务数据在 `data.json`（账号、白名单、管理员、圈子、油耗、Siri 配置、统计），没有数据库
- 备份：`cp data.json data-$(date +%F).json`，建议加个每日 cron
- 迁移：把 `data.json` 拷到新机器同一路径即可，密码哈希跟着走
- 重置：删掉 `data.json` 重启，会按 `ADMIN_PASS` / `DEMO_PIN` 重新生成种子数据

```bash
# 每日 3 点备份，保留 14 天
0 3 * * * cd /opt/car-replica && cp data.json backup/data-$(date +\%F).json && find backup -mtime +14 -delete
```

---

## 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 手机打不开 | 服务器安全组/防火墙没放行端口；或服务只监听 127.0.0.1，用 Nginx 反代或设 `HOST=0.0.0.0` |
| 页面能开、控车没反应 | 现在是本地模拟模式，属正常。真实控车见 README 的「真实模式」说明 |
| 登录提示「尝试过于频繁」 | 触发了限流，等 5 分钟或重启服务 |
| 管理弹层提示「管理密码错误」 | `ADMIN_PASS` 改了但 `data.json` 里还是旧哈希：删 `data.json` 重启，或改用旧密码验证后重设 |
| 上传图片失败 | Nginx `client_max_body_size` 太小，`nginx.conf` 里已给 30m |
| 国内打不开、海外正常 | 域名未备案，换香港/海外节点或完成备案 |

---

## 关于真实控车

上线后仍是**模拟数据**（车况是假车、指令不下发）。要接真实车辆，需要你在浏览器控制台打开真实模式：

```js
localStorage.setItem('replica_real_upstream','1'); location.reload();
```

并且具备真实的长安账号 `refresh_token`、车辆已开通车联网。若浏览器被跨域拦截，需要在 `server.py` 里加同源转发（`/real/iov/*` → 真实域名），这一步需要真实凭证才能联调。
