#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""远程控车系统 · 本地复刻后端

- 托管 site/ 静态前端（index / user_info / vehicle_status / guide）
- 复刻原站全部自有接口：登录、短信、卡密、权限、代理、管理后台、Siri、车友圈、油耗
- 复刻上游长安 iov / 高德接口（/mock/...）以便离线跑通控车流程
- 数据落 data.json，可重置

用法： python server.py [端口]
默认 http://127.0.0.1:8080
"""
import hashlib
import hmac
import json
import os
import random
import re
import string
import secrets
import sys
import threading
import time

import rsa_enc
import urllib.parse
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, "site")
DATA_FILE = os.environ.get("DATA_FILE", os.path.join(HERE, "data.json"))
LOG_FILE = os.environ.get("LOG_FILE", os.path.join(HERE, "requests.log"))

LOCK = threading.RLock()
REFRESH_LOCK = threading.Lock()   # refresh_token 换发必须串行，否则会被并发轮换作废

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
}

PAGE_ROUTES = {
    "/": "index.html",
    "/index.html": "index.html",
    "/user_info": "user_info.html",
    "/vehicle_status": "vehicle_status.html",
    "/guide": "guide.html",
    "/admin": "user_info.html",
}

DEMO_PHONE = os.environ.get("DEMO_PHONE", "13800138000")
DEMO_PIN = os.environ.get("DEMO_PIN", "123456")
ADMIN_PASS = os.environ.get("ADMIN_PASS", "admin888")
IS_PROD = os.environ.get("REPLICA_ENV", "dev").lower() in ("prod", "production")

# 登录/管理密码失败限流：{ip: [时间戳...]}
FAILS = {}
RATE_WINDOW = 300
RATE_MAX = 8


def pw_hash(pw, salt=None):
    salt = salt or secrets.token_hex(8)
    h = hashlib.pbkdf2_hmac("sha256", str(pw).encode(), salt.encode(), 120000).hex()
    return "pbkdf2$%s$%s" % (salt, h)


def pw_verify(pw, stored):
    """用存储里自带的盐校验口令（pw_hash 每次随机盐，不能直接比较）"""
    try:
        parts = str(stored or "").split("$")
        if len(parts) != 3 or parts[0] != "pbkdf2":
            return False
        salt, expect = parts[1], parts[2]
        calc = hashlib.pbkdf2_hmac("sha256", str(pw).encode(), salt.encode(), 120000).hex()
        return hmac.compare_digest(calc, expect)
    except Exception:
        return False


def pw_ok(pw, stored):
    if not stored:
        return False
    if stored.startswith("pbkdf2$"):
        _, salt, _ = stored.split("$", 2)
        return hmac.compare_digest(pw_hash(pw, salt), stored)
    return hmac.compare_digest(str(pw), str(stored))   # 兼容旧明文数据


def admin_ok(d, pw):
    return pw_ok(pw or "", d.get("admin_pass_hash"))


def rate_ok(ip):
    now = time.time()
    arr = [x for x in FAILS.get(ip, []) if now - x < RATE_WINDOW]
    FAILS[ip] = arr
    return len(arr) < RATE_MAX


def rate_fail(ip):
    FAILS.setdefault(ip, []).append(time.time())


# ----------------------------------------------------------------------------- 数据层
def seed():
    now = int(time.time())
    return {
        "users": {
            DEMO_PHONE: {
                "phone": DEMO_PHONE,
                "pin_hash": pw_hash(DEMO_PIN),
                "name": "演示车主",
                "created": now,
                "refresh_token": "rt_" + seed_token(),
                "whitelisted": True,
                "blocked": False,
                "agent": False,
                "cars": ["CAR_001"],
            }
        },
        "agents": [],
        "admins": [DEMO_PHONE],
        "owner": DEMO_PHONE,
        "admin_pass_hash": pw_hash(ADMIN_PASS),
        "whitelist_enabled": False,
        "myth_whitelist": [],
        "club": [
            {
                "id": 1, "phone": DEMO_PHONE, "nick": "演示车主", "avatar": "",
                "text": "复刻版跑起来了，控车页可以正常下发指令。",
                "images": [], "likes": 3, "liked": [], "comments": [],
                "time": now - 3600,
            },
            {
                "id": 2, "phone": "13900139000", "nick": "长安逸动", "avatar": "",
                "text": "周末跑了趟高速，续航表现还行。",
                "images": [], "likes": 1, "liked": [], "comments": [],
                "time": now - 86400,
            },
        ],
        "fuel": {
            DEMO_PHONE: [
                {"id": 1, "date": "2026-10-02", "ts": 1759417200, "odo": 18240,
                 "liters": 42.6, "price": 7.86, "amount": 334.84, "per100": 7.2,
                 "distance": 610},
                {"id": 2, "date": "2026-10-21", "ts": 1761058800, "odo": 18880,
                 "liters": 45.1, "price": 7.92, "amount": 357.19, "per100": 7.4,
                 "distance": 640},
            ]
        },
        "siri": {},
        "usage": {DEMO_PHONE: {"beats": 1, "last": now, "blocked": False}},
    }


def seed_token(n=32):
    return "".join(random.choice(string.ascii_letters + string.digits) for _ in range(n))


def load():
    with LOCK:
        if not os.path.exists(DATA_FILE):
            d = seed()
            save(d)
            return d
        try:
            with open(DATA_FILE, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            d = seed()
            save(d)
            return d


def save(d):
    with LOCK:
        tmp = DATA_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
        os.replace(tmp, DATA_FILE)


# ----------------------------------------------------------------------------- 车辆模拟数据
CAR = {
    "carId": "CAR_001",
    "carName": "长安 逸动 PLUS 2022",
    "plateNo": "渝A·8D6K2",
    "vin": "LS5A3DKR7NA000001",
    "model": "EadoPlus2022",
}


def car_data(seq=0):
    """模拟长安 m.iov/app2/api/car/data 返回的整车状态"""
    now = int(time.time())
    return {
        "code": 0,
        "success": True,
        "message": "ok",
        "data": {
            "carId": CAR["carId"],
            "carName": CAR["carName"],
            "plateNo": CAR["plateNo"],
            "updateTime": now,
            "timestamp": now,
            # 续航 / 油量 / 里程
            "remainedOilMile": 486 - seq % 7,
            "fuelLeftover": 41.2,
            "fuelPercent": 68,
            "totalOdometer": 19342,
            "igniteCumulativeMileage": 27.4,
            "igniteCumulativeOil": 2.1,
            # 电器
            "batteryVoltage": 12.4,
            "vehicleTemperature": 18, "environmentalTemp": 18,
            "acTemp": 24,
            "acStatus": 0,
            "temperature": 24,
            # 胎压 kPa
            "lfTyrePressure": 238, "rfTyrePressure": 236,
            "lrTyrePressure": 240, "rrTyrePressure": 239,
            # 状态位（0=正常/关闭，1=异常/开启）
            "lock": 1, "engine": 0, "engineStatus": 0, "engineSpeed": 0,
            "window": 0, "door": 0, "trunk": 0, "sunroof": 0,
            "speed": 0,
            # 系统自检（0=正常）
            "engineCoolantStatus": 0, "lowOilPressureFlag": 0,
            "vehicleStabilityControlSystemStatus": 0, "transmissionSystemStatus": 0,
            "absStatus": 0, "airbagSystemStatus": 0, "isValidGps": 1,
            "keyLowPower": 0, "signaIntensity": 4,
            "engineWaterTemp": 88, "ignitionTime": time.strftime("%Y-%m-%d %H:%M:%S"),
            # 空调
            "airConditioningSetTemperature": 24, "airRecycleStatus": 0,
            "air": {"temperature": 24, "status": 0, "mode": 0},
            # 门窗（0=关闭）
            "leftFrontDoorStatus": 0, "rightFrontDoorStatus": 0,
            "leftRearDoorStatus": 0, "rightRearDoorStatus": 0,
            "diverWindow": 0, "passengerWindow": 0,
            "leftRearWindow": 0, "rightRearWindow": 0,
            "hood": 0,
            # 灯光（0=关闭）
            "lowBeam": 0, "highBeam": 0, "positionLight": 0,
            "frontFoglamp": 0, "rearFoglamp": 0,
            # 位置
            "lat": 29.5630, "lng": 106.5516,
            "address": "重庆市渝北区龙兴镇两江大道",
            "direction": 90,
            "locationTime": now,
        },
    }


CAR_LIST = {
    "code": 0,
    "success": True,
    "data": [{
        "carId": CAR["carId"], "carName": CAR["carName"], "plateNo": CAR["plateNo"],
        "vin": CAR["vin"], "model": CAR["model"], "seriesName": "逸动 PLUS",
        "isNev": 0, "bindTime": int(time.time()) - 86400 * 200,
    }],
}


# ----------------------------------------------------------------------------- 真实上游（长安 iov / 高德）
REAL_UPSTREAMS = {
    "/real/iov/m": "https://m.iov.changan.com.cn",
    "/real/iov/incall": "https://incallapi.changan.com.cn",
    "/real/iov/open": "https://open.iov.changan.com.cn",
    "/real/amap": "https://dualstack-arestapi.amap.com",
}

REAL_UA = ("Mozilla/5.0 (Linux; Android 15; PKG110 Build/UKQ1.231108.001; wv) "
           "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0 Mobile Safari/537.36")


def _fresh_access_token(tk, d):
    """请求里带的 token → 服务端保存的最新 access_token（快过期就先续期）"""
    if not tk or not d:
        return tk
    try:
        with LOCK:
            snap = [(p, dict(u)) for p, u in (d.get("users") or {}).items()]
    except Exception:
        return tk
    for phone, u in snap:
        if u.get("real_access_token") != tk and u.get("real_refresh_token") != tk:
            continue
        exp = int(u.get("real_token_expire") or 0)
        cur = u.get("real_access_token") or ""
        if cur and exp and exp - 120 > time.time():
            return cur
        rt = u.get("real_refresh_token")
        if not rt:
            return tk
        try:
            j = _changan_refresh(rt)
            at = j.get("access_token")
            if at:
                with LOCK:
                    uu = d["users"].get(phone) or {}
                    uu["real_access_token"] = at
                    uu["real_refresh_token"] = j.get("refresh_token") or rt
                    uu["real_token_expire"] = int(time.time()) + int(j.get("expires_in") or 3600)
                    save(d)
                return at
        except Exception:
            pass
        return tk
    return tk


def proxy_real(path, query, method, raw_body, client_headers, d=None):
    """把 /real/* 转发到真实上游，规避浏览器跨域，并补齐客户端伪装头"""
    prefix = None
    for k in REAL_UPSTREAMS:
        if path.startswith(k):
            prefix = k
            break
    if not prefix:
        return 404, "application/json; charset=utf-8", b'{"success":false,"message":"unknown upstream"}'
    # refresh_token 换发统一在服务端串行处理：前端并发刷新会把旧凭证轮换作废
    if d and "/oauth2/refresh_token" in path:
        _m2 = re.search(r"(?:^|&)refresh_token=([^&]+)", query or "")
        if _m2:
            _old_rt = urllib.parse.unquote(_m2.group(1))
            try:
                with LOCK:
                    snap2 = [(p, dict(u)) for p, u in (d.get("users") or {}).items()]
                _ph = None
                for _p2, _u2 in snap2:
                    if _u2.get("real_refresh_token") == _old_rt:
                        _ph = _p2
                        break
                if _ph is None:
                    # 前端拿的是已被轮换掉的旧凭证，回落到服务端记录
                    for _p2, _u2 in snap2:
                        if _u2.get("real_refresh_token"):
                            _ph = _p2
                            break
                if _ph is not None:
                    with REFRESH_LOCK:
                        with LOCK:
                            _un = dict(d["users"].get(_ph) or {})
                        _exp = int(_un.get("real_token_expire") or 0)
                        if _exp - 60 > time.time() and _un.get("real_access_token"):
                            _cached = {"access_token": _un["real_access_token"],
                                       "refresh_token": _un.get("real_refresh_token"),
                                       "expires_in": max(1, _exp - int(time.time()))}
                            return 200, "application/json; charset=utf-8", json.dumps(_cached, ensure_ascii=False).encode()
                        _j = _changan_refresh(_un.get("real_refresh_token") or _old_rt)
                        _at = _j.get("access_token")
                        if _at:
                            with LOCK:
                                _uu = d["users"].get(_ph) or {}
                                _uu["real_access_token"] = _at
                                _uu["real_refresh_token"] = _j.get("refresh_token") or _old_rt
                                _uu["real_token_expire"] = int(time.time()) + int(_j.get("expires_in") or 3600)
                                save(d)
                            return 200, "application/json; charset=utf-8", json.dumps(_j, ensure_ascii=False).encode()
            except Exception:
                pass

    # 前端手里的 access_token 会过期，这里统一替换成服务端最新的（query + body 都要换）
    if d:
        _old_tk = None
        _new_tk = None
        if query:
            _m = re.search(r"(?:^|&)token=([^&]+)", query)
            if _m:
                _old_tk = urllib.parse.unquote(_m.group(1))
                _new_tk = _fresh_access_token(_old_tk, d)
                if _new_tk and _new_tk != _old_tk:
                    query = query[:_m.start(1)] + urllib.parse.quote(_new_tk) + query[_m.end(1):]
        # FormData / urlencoded 里的 token（控车 execute 就是这样带的）
        if raw_body and (not _new_tk):
            _mb = re.search(rb'(?:name="token"\r\n\r\n|(?:^|&)token=)([A-Za-z0-9_\-\.]{16,64})', raw_body)
            if _mb:
                _old_tk = _mb.group(1).decode("ascii", "ignore")
                _new_tk = _fresh_access_token(_old_tk, d)
        if _new_tk and _old_tk and _new_tk != _old_tk and raw_body:
            _ob = _old_tk.encode()
            if len(_new_tk) == len(_old_tk):
                raw_body = raw_body.replace(_ob, _new_tk.encode())

    url = REAL_UPSTREAMS[prefix] + path[len(prefix):]
    if query:
        url += ("&" if "?" in url else "?") + query

    headers = {
        "User-Agent": client_headers.get("User-Agent") or REAL_UA,
        "vcs-app-id": client_headers.get("vcs-app-id") or "inCall",
        "X-Requested-With": client_headers.get("X-Requested-With") or "cn.com.changan.cvim",
        "Accept": client_headers.get("Accept") or "application/json, text/plain, */*",
    }
    ct = client_headers.get("Content-Type")
    if ct:
        headers["Content-Type"] = ct

    # app-apigw / appgw 系列接口要求把 token 放在 X-VCS-User-Token 头里
    if d and ("/app-apigw/" in path or "/appgw/" in path):
        try:
            _ph, _at, _cid = _real_ctx({}, {}, d)
            if _at:
                headers["X-VCS-User-Token"] = _at
        except Exception:
            pass

    def _send_once():
        req = urllib.request.Request(url, data=(raw_body if method == "POST" else None),
                                     headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.headers.get("Content-Type") or "application/json", r.read()

    # 控车前先唤醒车辆，休眠状态下成功率明显更高
    if "control/execute" in path and method == "POST" and d:
        try:
            _p2, _at2, _cid2 = _real_ctx({}, {}, d)
            if _at2 and _cid2:
                changan_post("https://m.iov.changan.com.cn/app2/api/control/pre-wakeup",
                             {"carId": _cid2, "token": _at2})
        except Exception:
            pass

    # 控车限流：code=999「上一条指令尚未执行完成」，等几秒自动重试（指令未下发，重试不会重复执行）
    if "control/execute" in path and method == "POST":
        for _try in range(4):
            st, ct, rb = _send_once()
            if b'"code":999' not in rb and "999" not in rb[:80].decode("utf-8", "replace"):
                return st, ct, rb
            time.sleep(2.5)
        return st, ct, rb

    try:
        return _send_once()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type") or "application/json", e.read()
    except Exception as e:
        body = ('{"success":false,"message":"上游不可达：%s"}' % str(e)[:120]).encode()
        return 502, "application/json; charset=utf-8", body


# ----------------------------------------------------------------------------- 业务响应
def r_get_user_info(q, body, d):
    phone = (q.get("phone") or [""])[0] or body.get("phone", "")
    pin = (q.get("pin") or [""])[0] or body.get("pin", "")
    u = d["users"].get(phone)
    if not u:
        return {"success": False, "message": "用户不存在，请先短信登录"}
    if u.get("blocked"):
        return {"success": False, "message": "该账号已被限制登录"}
    stored = u.get("pin_hash") or u.get("pin")
    if not pin or not pw_ok(pin, stored):
        return {"success": False, "message": "控车码错误"}
    return {"success": True, "phone": phone, "pin": pin,
            "ref_token": u.get("refresh_token") or ("rt_" + seed_token()),
            "name": u.get("name", "")}


def r_check_phone(q, body, d):
    """登录前的手机号校验：只判断是否存在与被限制（卡密门槛已移除）"""
    phone = body.get("phone", "")
    u = d["users"].get(phone)
    if u and u.get("blocked"):
        return {"blocked": True, "exists": True, "message": "该手机号已被限制使用本网站"}
    if not u:
        # 复刻版无注册入口：新手机号直接放行，短信登录即自动建号
        return {"exists": True, "blocked": False, "new_user": True}
    return {"exists": True, "blocked": False}


def r_get_code(q, body, d):
    mobile = body.get("mobile", "")
    return {
        "success": True,
        "url": "/mock/upstream/sms",
        "method": "POST",
        "headers": {"Content-Type": "application/json"},
        "data": json.dumps({"mobile": mobile}, ensure_ascii=False),
    }


def r_register_user(q, body, d):
    return {
        "url": "/mock/upstream/oauth",
        "method": "POST",
        "headers": {"Content-Type": "application/x-www-form-urlencoded"},
        "data": urllib.parse.urlencode({
            "phone": body.get("phone", ""),
            "verifyCode": body.get("verifyCode", ""),
            "pin": body.get("pin", ""),
        }),
    }


def r_save_token(q, body, d):
    phone = body.get("phone", "")
    with LOCK:
        u = d["users"].setdefault(phone, {
            "phone": phone, "pin_hash": pw_hash(body.get("pin") or "123456"), "name": "新车主",
            "created": int(time.time()), "whitelisted": False, "blocked": False,
            "agent": False, "cars": ["CAR_001"],
        })
        u["refresh_token"] = body.get("refreshToken") or ("rt_" + seed_token())
        if body.get("pin"):
            u["pin_hash"] = pw_hash(body["pin"])
        u.pop("pin", None)
        save(d)
    return {"success": True}


def r_agent_check(q, body, d):
    phone = body.get("phone", "")
    return {
        "success": True,
        "is_admin": phone in d.get("admins", []),
        "is_agent": phone in d.get("agents", []),
        "is_owner": phone == d.get("owner"),
    }


def r_agent_list(q, body, d):
    return {"success": True, "list": d.get("agents", []), "agents": d.get("agents", [])}


def r_agent_add(q, body, d):
    phone = body.get("phone", "")
    with LOCK:
        if phone and phone not in d["agents"]:
            d["agents"].append(phone)
            save(d)
    return {"success": True, "message": "已添加代理"}


def r_agent_remove(q, body, d):
    phone = body.get("phone", "")
    with LOCK:
        if phone in d["agents"]:
            d["agents"].remove(phone)
            save(d)
    return {"success": True, "message": "已移除代理"}


def _wl_opts(d):
    return {
        "whitelist": [p for p, u in d["users"].items() if u.get("whitelisted")],
        "agents": d.get("agents", []),
        "admins": d.get("admins", []),
        "owner": d.get("owner"),
        "wl_enabled": d.get("whitelist_enabled", False),
    }


def _fmt_ts(ts):
    try:
        return time.strftime("%Y-%m-%d %H:%M", time.localtime(int(ts))) if ts else ""
    except Exception:
        return ""


def r_admin_usage(q, body, d):
    now = int(time.time())
    users = []
    for p, u in d["users"].items():
        st = d.get("usage", {}).get(p, {})
        users.append({
            "phone": p, "name": u.get("name", ""), "beats": st.get("beats", 0),
            "count": st.get("beats", 0),
            "first": _fmt_ts(u.get("created")),
            "last": _fmt_ts(st.get("last")),
            "last_ts": st.get("last", 0),
            "blocked": bool(st.get("blocked")),
            "agent": p in d.get("agents", []),
            "whitelisted": bool(u.get("whitelisted")),
            "wl": bool(u.get("whitelisted")),
            "owner": p == d.get("owner"),
            "admin": p in d.get("admins", []),
        })
    users.sort(key=lambda x: -int(x.get("last_ts") or 0))
    init = bool(d.get("admin_pass_hash") or d.get("admin_pass"))
    is_owner = body.get("caller") == d.get("owner")
    is_agent = body.get("caller") in d.get("agents", [])
    wl = [p for p, u in d["users"].items() if u.get("whitelisted")]
    blocked = [u["phone"] for u in users if u.get("blocked")]
    return {
        "success": True,
        "need_init": not init,
        "is_owner": is_owner,
        "is_agent": is_agent,
        "items": users,
        "people": len(users),
        "total": str(sum(u["beats"] for u in users)),
        "blocked": blocked,
        "admins": d.get("admins", []),
        "wl_enabled": d.get("whitelist_enabled", False),
        "whitelist": wl,
        "wl_creators": {},
        "people_wl": len(wl),
        "opts": _wl_opts(d),
        "stats": {
            "total_users": len(d["users"]),
            "online": sum(1 for u in users if now - u["last_ts"] < 300),
            "agents": len(d.get("agents", [])),
        },
        "users": users,
        "list": users,
    }


def r_admin_pass_init(q, body, d):
    with LOCK:
        if d.get("admin_pass_hash") and not admin_ok(d, body.get("old_password") or ""):
            return {"success": False, "message": "管理密码已存在，请先验证旧密码"}
        d["admin_pass_hash"] = pw_hash(body.get("password") or ADMIN_PASS)
        d.pop("admin_pass", None)
        if body.get("caller") and body["caller"] not in d["admins"]:
            d["admins"].append(body["caller"])
            if not d.get("owner"):
                d["owner"] = body["caller"]
        save(d)
    return {"success": True, "message": "管理密码已初始化"}


def r_admin_generic(q, body, d):
    return {"success": True, "message": "ok"}


def r_admin_admins_list(q, body, d):
    return {"success": True, "list": d.get("admins", []), "admins": d.get("admins", [])}


def r_admin_admins_add(q, body, d):
    with LOCK:
        p = body.get("phone")
        if p and p not in d["admins"]:
            d["admins"].append(p)
            save(d)
    return {"success": True}


def r_admin_admins_remove(q, body, d):
    with LOCK:
        p = body.get("phone")
        if p in d["admins"] and p != d.get("owner"):
            d["admins"].remove(p)
            save(d)
    return {"success": True}


def r_admin_is_admin(q, body, d):
    p = body.get("phone", "")
    return {"success": True, "is_admin": p in d.get("admins", []), "is_owner": p == d.get("owner")}


def r_auth_status(q, body, d):
    phone = body.get("phone", "")
    u = d["users"].get(phone)
    if not u:
        return {"ok": False, "message": "账号不存在"}
    if u.get("blocked"):
        return {"ok": False, "message": "该账号已被限制登录"}
    if body.get("pin") and not pw_ok(body["pin"], u.get("pin_hash") or u.get("pin")):
        return {"ok": False, "message": "登录凭证已失效，请重新登录"}
    return {"ok": True}


def r_auth_revoke(q, body, d):
    target = body.get("target", "")
    with LOCK:
        u = d["users"].get(target)
        if u:
            u["blocked"] = True
            save(d)
    return {"success": True, "message": "对方已被强制下线"}


def r_usage_beat(q, body, d):
    p = body.get("phone", "")
    with LOCK:
        st = d.setdefault("usage", {}).setdefault(p, {"beats": 0, "last": 0, "blocked": False})
        st["beats"] += 1
        st["last"] = int(time.time())
        save(d)
    return {"success": True}


def r_myth_check(q, body, d):
    p = body.get("phone", "")
    return {"success": True, "allowed": True, "white": p in d.get("myth_whitelist", []),
            "is_admin": p in d.get("admins", [])}


def r_myth_wl_list(q, body, d):
    return {"success": True, "list": d.get("myth_whitelist", []), "whitelist": d.get("myth_whitelist", [])}


def r_myth_wl_add(q, body, d):
    with LOCK:
        p = body.get("phone")
        if p and p not in d["myth_whitelist"]:
            d["myth_whitelist"].append(p)
            save(d)
    return {"success": True}


def r_myth_wl_remove(q, body, d):
    with LOCK:
        p = body.get("phone")
        if p in d["myth_whitelist"]:
            d["myth_whitelist"].remove(p)
            save(d)
    return {"success": True}


def _siri_cfg(d, phone):
    st = d.setdefault("siri", {}).setdefault(phone, {
        "enabled": False, "key": "siri_" + seed_token(24),
        "cmds": {"锁车": "lock", "解锁": "unlock", "开空调": "ac_on", "关空调": "ac_off"},
        "car_id": CAR["carId"],
    })
    save(d)
    return st


def r_siri_config(q, body, d):
    st = _siri_cfg(d, body.get("phone", ""))
    return {"success": True, **st}


def r_siri_toggle(q, body, d):
    st = _siri_cfg(d, body.get("phone", ""))
    with LOCK:
        st["enabled"] = bool(body.get("enabled"))
        save(d)
    return {"success": True, **st}


def r_siri_cmds(q, body, d):
    st = _siri_cfg(d, body.get("phone", ""))
    with LOCK:
        if isinstance(body.get("cmds"), dict):
            st["cmds"] = body["cmds"]
            save(d)
    return {"success": True, **st}


def r_siri_cars(q, body, d):
    return {"success": True, "cars": CAR_LIST["data"], "list": CAR_LIST["data"]}


def r_siri_car(q, body, d):
    st = _siri_cfg(d, body.get("phone", ""))
    with LOCK:
        st["car_id"] = body.get("car_id", CAR["carId"])
        save(d)
    return {"success": True, **st}


def r_siri_log(q, body, d):
    return {"success": True, "list": [], "logs": []}


def r_siri_key_reset(q, body, d):
    st = _siri_cfg(d, body.get("phone", ""))
    with LOCK:
        st["key"] = "siri_" + seed_token(24)
        save(d)
    return {"success": True, **st}


def _car_data(at, cid):
    """拉全量车况（car/data 必须 POST）"""
    try:
        return changan_post("https://m.iov.changan.com.cn/app2/api/car/data?carId=" + urllib.parse.quote(cid)
                            + "&ErrorAutoProjectile=false&toast=false&keys=*&isNev=0&token="
                            + urllib.parse.quote(at), {}).get("data") or {}
    except Exception:
        return {}


SIRI_CMDS = {
    "lock": "LockDoor", "unlock": "UnLockDoor",
    "close_window": "CloseWindow", "open_window": "OpenWindow",
    "flash": "FlashLight", "search": "RemoteSearchCar",
    "ac_on": "openair", "ac_off": "closeair",
    "engine_on": "OpenEngine", "engine_off": "CloseEngine",
}


def _do_cmd(cmd):
    """服务端下发控车指令（自动处理 pinVerifyCode + 公钥 + 加密）"""
    d = load()
    phone, at, cid = _real_ctx({}, {}, d)
    if not at or not cid:
        return {"success": False, "message": "未登录"}
    cfg = d.get("auto_close") or {}
    pin = cfg.get("pin") or ""
    if not pin:
        return {"success": False, "message": "未设置控车码"}
    HDR = "https://m.iov.changan.com.cn"
    try:
        code = (changan_post(HDR + "/app2/api/control/createPinVerifyCode?carId=" + urllib.parse.quote(cid)
                             + "&token=" + urllib.parse.quote(at) + "&isNev=0", {}).get("data") or "")
        pub = changan_get(HDR + "/app2/api/v2/security/key?carId=" + urllib.parse.quote(cid)
                          + "&token=" + urllib.parse.quote(at)).get("data") or ""
        pt = json.dumps({"cmd": cmd, "type": cmd, "pin": pin, "pinVerifyCode": code}, ensure_ascii=False)
        cipher = rsa_enc.encrypt_oaep(pub, pt, "sha256")
        r = changan_post(HDR + "/app2/api/v3/control/execute",
                         {"carId": cid, "token": at, "isNev": 0, "s": cipher})
        return {"success": bool(r.get("success")), "code": r.get("code"), "message": r.get("msg") or ""}
    except Exception as e:
        return {"success": False, "message": str(e)[:90]}


def r_siri_exec(q, body, d):
    phone = (q.get("phone") or [""])[0]
    act = (q.get("act") or [""])[0]
    key = (q.get("key") or [""])[0]
    st = d.get("siri", {}).get(phone)
    if not st:
        return {"success": False, "message": "Siri 未配置"}
    if key != st.get("key"):
        return {"success": False, "message": "密钥错误"}
    if not st.get("enabled"):
        return {"success": False, "message": "Siri 控车未开启"}
    if act == "status":
        _ph, at, cid = _real_ctx({}, {}, d)
        if not at or not cid:
            return {"success": False, "message": "未登录"}
        sd = _car_data(at, cid)
        return {"success": True, "action": "status", "fuel": sd.get("fuelLeftover"),
                "range": sd.get("remainedOilMile"), "locked": str(sd.get("door")) == "0",
                "voltage": sd.get("batteryVoltage")}
    real = SIRI_CMDS.get(act) or act
    r = _do_cmd(real)
    r["action"] = real
    return r


def r_club_list(q, body, d):
    return {"success": True, "list": d.get("club", []), "posts": d.get("club", [])}


def r_club_post(q, body, d):
    with LOCK:
        posts = d.setdefault("club", [])
        pid = max([p["id"] for p in posts] or [0]) + 1
        posts.insert(0, {
            "id": pid, "phone": body.get("phone", ""), "nick": body.get("nick") or "车主",
            "avatar": body.get("avatar", ""), "text": body.get("text", ""),
            "images": body.get("images") or [], "likes": 0, "liked": [],
            "comments": [], "time": int(time.time()),
        })
        save(d)
    return {"success": True, "id": pid}


def r_club_like(q, body, d):
    pid = body.get("id")
    phone = body.get("phone", "")
    with LOCK:
        for p in d.get("club", []):
            if p["id"] == pid:
                liked = p.setdefault("liked", [])
                if phone in liked:
                    liked.remove(phone)
                    p["likes"] = max(0, p.get("likes", 1) - 1)
                else:
                    liked.append(phone)
                    p["likes"] = p.get("likes", 0) + 1
                save(d)
                return {"success": True, "likes": p["likes"], "liked": phone in liked}
    return {"success": False, "message": "帖子不存在"}


def r_club_comment(q, body, d):
    pid = body.get("id")
    with LOCK:
        for p in d.get("club", []):
            if p["id"] == pid:
                cs = p.setdefault("comments", [])
                cs.append({"phone": body.get("phone", ""), "nick": body.get("nick") or "车主",
                           "text": body.get("text", ""), "time": int(time.time())})
                save(d)
                return {"success": True, "comments": cs}
    return {"success": False, "message": "帖子不存在"}


def r_club_view(q, body, d):
    pid = body.get("id")
    for p in d.get("club", []):
        if p["id"] == pid:
            return {"success": True, "post": p}
    return {"success": False, "message": "帖子不存在"}


def r_club_delete(q, body, d):
    with LOCK:
        d["club"] = [p for p in d.get("club", []) if p["id"] != body.get("id")]
        save(d)
    return {"success": True}


def r_club_upload(q, body, d):
    return {"success": True, "url": "/static/img/car_side.png"}


def r_fuel_log(q, body, d):
    phone = body.get("phone") or (q.get("phone") or [DEMO_PHONE])[0]
    recs = d.get("fuel", {}).get(phone, [])
    per = [r["per100"] for r in recs if r.get("per100")]
    return {
        "success": True,
        "records": recs,
        "avg_per100": round(sum(per) / len(per), 1) if per else None,
        "latest_per100": per[-1] if per else None,
    }


def r_fuel_delete(q, body, d):
    phone = body.get("phone") or DEMO_PHONE
    with LOCK:
        recs = d.get("fuel", {}).get(phone, [])
        d.setdefault("fuel", {})[phone] = [r for r in recs if r.get("id") != body.get("id")]
        save(d)
    return {"success": True}


def r_encrypt(q, body, d):
    """有公钥就做真实 RSA/PKCS1 加密，否则退回模拟"""
    pt = body.get("plaintext", "")
    # 长安不接受明文里多余的 wifiPassword 字段（会返回 code=10 指令异常），这里剔除
    try:
        _o = json.loads(pt)
        if isinstance(_o, dict) and "wifiPassword" in _o:
            _o.pop("wifiPassword", None)
            pt = json.dumps(_o, ensure_ascii=False)
    except Exception:
        pass
    pub = (body.get("public_key") or "").strip()
    if pub:
        try:
            cipher = rsa_enc.encrypt_oaep(pub, pt, "sha256")   # 长安控车用 OAEP-SHA256
            return {"success": True, "data": cipher, "ciphertext": cipher,
                    "encrypted_data": cipher, "encryptedData": cipher}
        except Exception as e:
            return {"success": False, "message": "加密失败：%s" % str(e)[:120]}
    _mock = "MOCKENC:" + pt
    return {"success": True, "data": _mock, "ciphertext": _mock, "encrypted_data": _mock}


CHANGAN_HEADERS = {
    "Accept": "*/*",
    "User-Agent": "ChanganInCall/5.2.0 (iPhone; iOS 15.0; Scale/3.00)",
    "X-Requested-With": "cn.com.changan.cvim",
}


def changan_post(url, form):
    """按长安 App 的请求格式发 POST（表单编码）"""
    data = urllib.parse.urlencode(form).encode()
    h = dict(CHANGAN_HEADERS)
    h["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=data, headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def changan_get(url):
    """按长安 App 的请求格式发 GET"""
    req = urllib.request.Request(url, headers=dict(CHANGAN_HEADERS), method="GET")
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def r_real_sms(q, body, d):
    """真实短信发码：手机号 → 长安下发 6 位验证码"""
    phone = (body.get("phone") or "").strip()
    if not re.match(r"^1\d{10}$", phone):
        return {"success": False, "message": "手机号格式不正确（需 11 位）"}
    try:
        r = changan_post("https://m.iov.changan.com.cn/api/sms/sendAuthcode", {"phone": phone})
    except Exception as e:
        return {"success": False, "message": "发码失败：%s" % str(e)[:120]}
    ok = bool(r.get("success"))
    return {"success": ok, "message": r.get("msg") or ("验证码已发送" if ok else "发送失败")}


CHANGAN_CLIENT_ID = "2c918082632162010163388048d60158"


def _changan_refresh(refresh_token):
    """用 refresh_token 换新的 access_token（顺带拿轮换后的 refresh_token）"""
    url = ("https://incallapi.changan.com.cn/cac/api/v1/oauth2/refresh_token?client_id="
           + CHANGAN_CLIENT_ID + "&refresh_token=" + urllib.parse.quote(refresh_token))
    req = urllib.request.Request(url, headers={
        "Accept": "*/*", "User-Agent": "okhttp/4.9.0", "response-form": "json"}, method="GET")
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def _real_car_meta(phone, access_token, d):
    """拉一次车辆信息，回填并返回车名/车牌/carId"""
    car_name = plate = car_id = vin = ""
    try:
        cars = changan_get("https://m.iov.changan.com.cn/app2/api/user/cars?type=0&token="
                           + urllib.parse.quote(access_token))
        row = (cars.get("data") or [{}])[0]
        car_name = row.get("carName") or ""
        plate = row.get("plateNumber") or ""
        car_id = row.get("carId") or ""
        vin = row.get("vin") or ""
        with LOCK:
            u = d["users"].get(phone) or {}
            if u:
                u.update({"real_car_name": car_name, "real_plate": plate,
                          "real_car_id": car_id, "real_vin": vin})
                save(d)
    except Exception:
        pass
    return car_name, plate, car_id, vin


def _real_ctx(body, q, d):
    """取当前真实用户的 token 与 carId"""
    phone = (body.get("phone") or (q.get("phone") or [""])[0] or "").strip()
    with LOCK:
        if phone:
            u = dict(d["users"].get(phone) or {})
        else:
            u = {}
            for _p, _uu in (d.get("users") or {}).items():
                if _uu.get("real_access_token"):
                    u = dict(_uu)
                    phone = _p
                    break
    return phone, (u.get("real_access_token") or ""), (u.get("real_car_id") or "")


def r_real_location(q, body, d):
    """车辆位置（地址 + 经纬度 + 速度）"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at or not cid:
        return {"success": False, "message": "未登录"}
    try:
        j = changan_get("https://m.iov.changan.com.cn/app2/api/car/location?carId="
                        + urllib.parse.quote(cid)
                        + "&mapType=GCJ02&ErrorAutoProjectile=false&toast=false&token="
                        + urllib.parse.quote(at)
                        + "&isNev=0&deviceId=00000000-5768-bcb8-ffff-ffffef05ac4a")
        dt = j.get("data") or {}
        return {"success": True,
                "address": dt.get("address") or "",
                "city": dt.get("city") or "",
                "lat": dt.get("lat"),
                "lng": dt.get("lng"),
                "speed": dt.get("speed"),
                "gpsTime": dt.get("gpsTime") or ""}
    except Exception as e:
        return {"success": False, "message": str(e)[:90]}


def r_auto_config(q, body, d):
    """读取/设置自动关窗配置"""
    with LOCK:
        ac = d.setdefault("auto_close", {})
        if body.get("set"):
            if "enabled" in body:
                ac["enabled"] = bool(body["enabled"])
            if body.get("bark_key"):
                ac["bark_key"] = str(body["bark_key"]).strip()
            if body.get("pin"):
                ac["pin"] = str(body["pin"]).strip()
            if "auto_lock_at" in body:
                ac["auto_lock_at"] = str(body.get("auto_lock_at") or "").strip()
            if body.get("siri_token"):
                d["siri_token"] = str(body["siri_token"]).strip()
            save(d)
        return {"success": True, "enabled": bool(ac.get("enabled")),
                "bark_key": ac.get("bark_key") or "", "has_pin": bool(ac.get("pin")),
                "auto_lock_at": ac.get("auto_lock_at") or "",
                "siri_token": d.get("siri_token") or "",
                "last_sig": ac.get("last_sig") or "", "last_time": ac.get("last_time"),
                "last_ok": ac.get("last_ok")}


def r_real_energy(q, body, d):
    """近 7 天能耗/里程趋势"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at or not cid:
        return {"success": False, "message": "未登录"}
    # 今天没开车时接口返回空，往前找最近一个有数据的日子
    for back in range(0, 8):
        ts = time.time() - back * 86400
        d1 = time.strftime("%Y-%m-%d", time.localtime(ts))
        d2 = time.strftime("%Y%m%d", time.localtime(ts))
        try:
            j = changan_get("https://m.iov.changan.com.cn/app2/api/car-report/car-energy-trend?carId="
                            + urllib.parse.quote(cid) + "&queryType=0&date=" + d1
                            + "&queryDay=" + d2 + "&token=" + urllib.parse.quote(at))
        except Exception as e:
            return {"success": False, "message": str(e)[:90]}
        dt = j.get("data") or {}
        fuel = dt.get("fuelAvgList") or []
        if any(str(x) not in ("0", "0.0", "") for x in fuel) or (dt.get("dateList") or []):
            # 顺带取今年月度趋势（queryType=1）
            months, mfuel = [], []
            try:
                jm = changan_get("https://m.iov.changan.com.cn/app2/api/car-report/car-energy-trend?carId="
                                 + urllib.parse.quote(cid) + "&queryType=1&date=" + d1
                                 + "&queryDay=" + d2 + "&token=" + urllib.parse.quote(at))
                md = jm.get("data") or {}
                months = md.get("dateList") or []
                mfuel = md.get("fuelAvgList") or []
            except Exception:
                pass
            return {"success": True, "day": d2,
                    "dates": dt.get("dateList") or [],
                    "fuel": fuel,
                    "mileage": dt.get("igniteCumulativeMileage") or [],
                    "fuelAvg": dt.get("fuelAvg") or "",
                    "seriesFuelAvg": dt.get("seriesFuelAvg") or "",
                    "months": months, "monthFuel": mfuel}
    return {"success": True, "day": "", "dates": [], "fuel": [], "mileage": [],
            "fuelAvg": "", "seriesFuelAvg": ""}


def r_real_report(q, body, d):
    """当日驾驶报告（评分/急加速/急减速等）"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at or not cid:
        return {"success": False, "message": "未登录"}
    dt = {}
    for back in range(0, 8):
        day = time.strftime("%Y%m%d", time.localtime(time.time() - back * 86400))
        try:
            j = changan_get("https://m.iov.changan.com.cn/app2/api/car-report/car-report-day?carId="
                            + urllib.parse.quote(cid) + "&queryDay=" + day + "&token=" + urllib.parse.quote(at))
        except Exception as e:
            return {"success": False, "message": str(e)[:90]}
        dt = j.get("data") or {}
        if dt.get("drivingScore") is not None:
            break
    return {"success": True,
            "score": dt.get("drivingScore"),
            "fuel": dt.get("fuelAvg"),
            "mileage": dt.get("igniteCumulativeMileage"),
            "rapidAcc": dt.get("rapidAccelerationCnt"),
            "rapidDec": dt.get("rapidDecelerationCnt"),
            "sharpTurn": dt.get("sharpTurnCnt"),
            "nightP": dt.get("nightDrivingHourP"),
            "fatigueP": dt.get("fatigueDrivingHourP")}


def r_oil_price(q, body, d):
    """当日油价（四川默认），缓存 6 小时"""
    prov = (body.get("prov") if body else None) or (q.get("prov") or ["四川"])[0]
    cache = d.get("oil_cache") or {}
    now = time.time()
    if cache.get("prov") == prov and (now - (cache.get("at") or 0)) < 21600 and cache.get("p92"):
        return {"success": True, "prov": cache.get("prov"), "p92": cache.get("p92"),
                "p95": cache.get("p95"), "p98": cache.get("p98"),
                "time": cache.get("time"), "cached": True}
    try:
        j = changan_get("https://api.qqsuu.cn/api/dm-oilprice?prov=" + urllib.parse.quote(prov))
        dt = j.get("data") or {}
        if not dt.get("p92"):
            raise ValueError("empty")
        out = {"success": True, "prov": dt.get("prov") or prov, "p92": dt.get("p92"),
               "p95": dt.get("p95"), "p98": dt.get("p98"), "time": dt.get("time")}
        with LOCK:
            d["oil_cache"] = {**out, "prov": prov, "at": int(now)}
            save(d)
        return out
    except Exception as e:
        if cache.get("p92"):
            return {"success": True, "prov": cache.get("prov"), "p92": cache.get("p92"),
                    "p95": cache.get("p95"), "p98": cache.get("p98"),
                    "time": cache.get("time"), "cached": True}
        return {"success": False, "message": str(e)[:80]}


def r_real_checkitems(q, body, d):
    """车辆自检项（按系统分组）"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at or not cid:
        return {"success": False, "message": "未登录"}
    try:
        j = changan_post("https://m.iov.changan.com.cn/appserver/api/carcheck/getAllCheckItem?carId="
                         + urllib.parse.quote(cid) + "&token=" + urllib.parse.quote(at), {})
        arr = j.get("data") or []
        groups = []
        for g in arr[:12]:
            kids = g.get("child") or []
            groups.append({"name": g.get("nodeName") or "", "count": len(kids),
                           "items": [k.get("nodeName") for k in kids[:6]]})
        return {"success": True, "total": len(arr), "groups": groups}
    except Exception as e:
        return {"success": False, "message": str(e)[:90]}


def r_real_maintenance(q, body, d):
    """下次保养建议 + 保养历史"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at or not cid:
        return {"success": False, "message": "未登录"}
    out = {"success": True, "advices": [], "history": []}
    try:
        j = changan_get("https://m.iov.changan.com.cn/mt/uc/api/maintenance/next?carId="
                        + urllib.parse.quote(cid) + "&appVersion=3.2.0&token=" + urllib.parse.quote(at))
        for a in ((j.get("data") or {}).get("advices") or [])[:6]:
            out["advices"].append({
                "name": a.get("maintenanceName") or "",
                "left": a.get("remainPercentage"),
                "nextMileage": a.get("nextMileage"),
                "nextDays": a.get("nextTime"),
                "advise": a.get("advise") or ""})
    except Exception:
        pass
    try:
        j2 = changan_get("https://m.iov.changan.com.cn/mt/uc/api/maintenance/history?currentPage=1&pageSize=5&carId="
                         + urllib.parse.quote(cid) + "&token=" + urllib.parse.quote(at))
        for h in ((j2.get("data") or {}).get("list") or [])[:5]:
            out["history"].append({
                "items": h.get("maintainItem") or "",
                "mile": h.get("maintainMile"),
                "time": (h.get("maintainTime") or "")[:10],
                "dealer": h.get("dealerName") or ""})
    except Exception:
        pass
    return out


def r_real_unread(q, body, d):
    """未读消息数（appserver/api/information/getUnReadInfoNumber）"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at:
        return {"success": False, "message": "未登录"}
    try:
        j = changan_post("https://m.iov.changan.com.cn/appserver/api/information/getUnReadInfoNumber",
                         {"actionType": 1, "deviceId": "00000000-5768-bcb8-ffff-ffffef05ac4a",
                          "isNev": 0, "token": at})
        v = j.get("data")
        return {"success": True, "count": int(v) if str(v).isdigit() else 0}
    except Exception as e:
        return {"success": False, "message": str(e)[:90]}


def r_real_cardetail(q, body, d):
    """车辆详情：车色 / 油品 / 昵称等"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at:
        return {"success": False, "message": "未登录"}
    if not cid:
        return {"success": False, "message": "缺少车辆信息"}
    try:
        j = changan_get("https://m.iov.changan.com.cn/app2/api/v3/car/detail?carId="
                        + urllib.parse.quote(cid) + "&token=" + urllib.parse.quote(at))
        dt = j.get("data") or {}
        return {"success": True,
                "color": dt.get("color") or "",
                "oilType": dt.get("oilType") or "",
                "nickname": dt.get("userNickname") or "",
                "confName": dt.get("confName") or "",
                "plate": dt.get("plateNumber") or "",
                "realname": dt.get("realnameAuthStatus") or "",
                "service": dt.get("tserviceStatus") or ""}
    except Exception as e:
        return {"success": False, "message": str(e)[:90]}


def r_real_balance(q, body, d):
    """车机流量余额"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at or not cid:
        return {"success": False, "message": "未登录"}
    try:
        j = changan_get("https://m.iov.changan.com.cn/app2/api/mall/digital/balance/app?carId="
                        + urllib.parse.quote(cid) + "&token=" + urllib.parse.quote(at))
        arr = j.get("data") or []
        out = []
        for it in arr[:5]:
            ai = it.get("appInfo") or {}
            out.append({"name": ai.get("appName") or "", "total": it.get("total")})
        return {"success": True, "items": out}
    except Exception as e:
        return {"success": False, "message": str(e)[:90]}


def r_real_profile(q, body, d):
    """座椅/后视镜等记忆参数（只取有值的）"""
    phone, at, cid = _real_ctx(body, q, d)
    if not at or not cid:
        return {"success": False, "message": "未登录"}
    try:
        j = changan_get("https://m.iov.changan.com.cn/app2/api/user-profile/get-profile?carId="
                        + urllib.parse.quote(cid) + "&token=" + urllib.parse.quote(at))
        prof = (j.get("data") or {}).get("profile") or []
        items = [{"name": x.get("name"), "value": x.get("value")} for x in prof[:30]]
        return {"success": True, "count": len(prof), "items": items}
    except Exception as e:
        return {"success": False, "message": str(e)[:90]}


def r_real_online(q, body, d):
    """车辆在线状态（appgw/v1/app2/api/car-online/status）"""
    phone = (body.get("phone") or (q.get("phone") or [""])[0] or "").strip()
    if not phone:
        with LOCK:
            for _p, _u in (d.get("users") or {}).items():
                if _u.get("real_access_token"):
                    phone = _p
                    break
    u = d["users"].get(phone) or {}
    at = u.get("real_access_token") or ""
    if not at:
        return {"success": False, "message": "未登录"}
    try:
        j = changan_get("https://m.iov.changan.com.cn/appgw/v1/app2/api/car-online/status?X-VCS-User-Token="
                        + urllib.parse.quote(at))
        return {"success": True, "online": bool((j.get("data") or {}).get("online"))}
    except Exception as e:
        return {"success": False, "message": str(e)[:80]}


def r_real_session(q, body, d):
    """免验证码登录：手机号 + 控车码 → 用服务端保存的 token 直接进（换浏览器也能用）"""
    phone = (body.get("phone") or "").strip()
    pin = (body.get("pin") or "").strip()
    if not re.match(r"^1\d{10}$", phone):
        return {"success": False, "message": "手机号格式不正确"}
    with LOCK:
        u = d["users"].get(phone) or {}
        rt = u.get("real_refresh_token") or ""
        pin_hash = u.get("pin_hash") or ""
    if not rt:
        return {"success": False, "need_sms": True,
                "message": "这台手机号还没有登录记录，请先用短信验证码登录一次"}
    if not pin:
        return {"success": False, "message": "请输入控车码"}
    if pin_hash and not pw_verify(pin, pin_hash):
        return {"success": False, "message": "控车码不正确"}
    try:
        j = _changan_refresh(rt)
    except Exception as e:
        return {"success": False, "message": "登录凭证刷新失败：%s" % str(e)[:100]}
    at = j.get("access_token") or ""
    nrt = j.get("refresh_token") or rt
    if not at:
        return {"success": False, "need_sms": True, "message": "凭证已失效，请用验证码重新登录一次"}
    with LOCK:
        u = d["users"].setdefault(phone, {})
        u["real_mode"] = True
        u["real_access_token"] = at
        u["real_refresh_token"] = nrt
        u["real_token_expire"] = int(time.time()) + int(j.get("expires_in") or 3600)
        save(d)
    car_name, plate, car_id, vin = _real_car_meta(phone, at, d)
    return {"success": True, "message": "登录成功", "access_token": at,
            "refresh_token": nrt, "car_name": car_name, "plate": plate,
            "car_id": car_id, "vin": vin}


def r_real_login(q, body, d):
    """验证码登录：mobile + vercode → access_token / refresh_token"""
    phone = (body.get("phone") or "").strip()
    code = (body.get("code") or body.get("vercode") or "").strip()
    pin = (body.get("pin") or "").strip()
    print("[real/login] keys=%s phone=%s code_len=%d pin_len=%d"
          % (list(body.keys()), phone[:3] + "****" if phone else "(空)",
             len(code), len(pin)), flush=True)
    if not phone or not code:
        return {"success": False, "message": "缺少手机号或验证码"}
    try:
        r = changan_post("https://m.iov.changan.com.cn/app2/api/oauth2login/token/stageOne",
                         {"mobile": phone, "vercode": code})
    except Exception as e:
        return {"success": False, "message": "登录请求失败：%s" % str(e)[:120]}
    data = r.get("data") or {}
    at = data.get("access_token") or ""
    rt = data.get("refresh_token") or ""
    if not at:
        return {"success": False, "message": r.get("msg") or "验证码错误或已过期"}
    with LOCK:
        u = d["users"].setdefault(phone, {
            "phone": phone, "pin_hash": pw_hash(pin or "123456"),
            "name": "车主" + phone[-4:], "created": int(time.time()),
            "whitelisted": True, "blocked": False, "agent": False, "cars": ["CAR_001"],
        })
        u["real_mode"] = True
        u["real_access_token"] = at
        u["real_refresh_token"] = rt
        u["real_token_expire"] = int(time.time()) + int(data.get("expires_in") or 3600)
        u["real_openid"] = data.get("openid") or ""
        if pin:
            u["pin_hash"] = pw_hash(pin)
        save(d)
    # 登录后顺手把真实车辆信息取回来，供前端显示车名/车牌
    car_name, plate, car_id, vin = "", "", "", ""
    try:
        cars = changan_get("https://m.iov.changan.com.cn/app2/api/user/cars?type=0&token="
                           + urllib.parse.quote(at))
        row = (cars.get("data") or [{}])[0]
        car_name = row.get("carName") or ""
        plate = row.get("plateNumber") or ""
        car_id = row.get("carId") or ""
        vin = row.get("vin") or ""
        with LOCK:
            u = d["users"].get(phone) or {}
            if u:
                u.update({"real_car_name": car_name, "real_plate": plate,
                          "real_car_id": car_id, "real_vin": vin})
                save(d)
    except Exception:
        pass
    return {"success": True, "message": "登录成功", "access_token": at,
            "refresh_token": rt, "expires_in": int(data.get("expires_in") or 3600),
            "openid": data.get("openid") or "",
            "car_name": car_name, "plate": plate, "car_id": car_id, "vin": vin}


def r_real_token(q, body, d):
    """保存真实长安账号的 refresh_token，供前端真实模式使用"""
    phone = body.get("phone", "")
    rt = (body.get("refresh_token") or "").strip()
    if not phone or not rt:
        return {"success": False, "message": "缺少手机号或 refresh_token"}
    with LOCK:
        u = d["users"].setdefault(phone, {
            "phone": phone, "pin_hash": pw_hash(body.get("pin") or "123456"),
            "name": "车主" + phone[-4:], "created": int(time.time()),
            "whitelisted": True, "blocked": False, "agent": False, "cars": ["CAR_001"],
        })
        u["real_refresh_token"] = rt
        u["real_mode"] = True
        if body.get("pin"):
            u["pin_hash"] = pw_hash(body["pin"])
        save(d)
    return {"success": True, "message": "已接入真实车辆"}


def r_real_status(q, body, d):
    phone = body.get("phone", "") or (q.get("phone") or [""])[0]
    u = d["users"].get(phone) or {}
    return {"success": True, "real_mode": bool(u.get("real_mode")),
            "has_token": bool(u.get("real_refresh_token")),
            "token_tail": (u.get("real_refresh_token") or "")[-6:]}


def r_get_scode(q, body, d):
    return {"key": "mock-amap-key", "ts": int(time.time()), "scode": seed_token(16)}


def r_ac_qrcode(q, body, d):
    return {"success": True, "qrcode_id": "qr_" + seed_token(8),
            "expire": int(time.time()) + 120, "message": "请用手机扫码确认"}


def r_ac_status(q, body, d):
    if not (q.get("qrcode_id") or [""])[0]:
        return {"success": False, "message": "缺少 qrcode_id"}
    return {"success": True, "status": "waiting", "message": "等待手机端确认"}


def r_open_token(q, body, d):
    return {"success": True, "access_token": "mock_open_at", "refresh_token": "mock_open_rt",
            "expires_in": 7200, "data": {"access_token": "mock_open_at",
                                         "refresh_token": "mock_open_rt", "expires_in": 7200}}


def r_ok(q, body, d):
    return {"success": True, "message": "ok"}


# ---- 上游长安/高德模拟 ----
def u_oauth_refresh(q, body, d):
    return {"access_token": "mock_at_" + seed_token(12),
            "refresh_token": "mock_rt_" + seed_token(12),
            "expires_in": 7200, "token_type": "bearer", "success": True}


def u_sms(q, body, d):
    return {"success": True, "message": "验证码已发送（模拟）", "code": "123456"}


def u_register(q, body, d):
    phone = body.get("phone", "")
    with LOCK:
        u = d["users"].setdefault(phone, {
            "phone": phone, "pin_hash": pw_hash(body.get("pin") or "123456"),
            "name": "车主" + phone[-4:], "created": int(time.time()),
            "whitelisted": False, "blocked": False, "agent": False,
            "cars": ["CAR_001"],
        })
        u["refresh_token"] = "mock_rt_" + seed_token(20)
        if body.get("pin"):
            u["pin_hash"] = pw_hash(body["pin"])
        save(d)
    return {"success": True, "code": 0, "data": {
        "access_token": "mock_at_" + seed_token(12),
        "refresh_token": u["refresh_token"],
        "expires_in": 7200,
    }}


def u_cars(q, body, d):
    return CAR_LIST


def u_car_data(q, body, d):
    return car_data()


def u_control(q, body, d):
    return {"code": 0, "success": True, "message": "指令下发成功（模拟）",
            "data": {"result": 1, "ts": int(time.time())}}


def u_security_key(q, body, d):
    return {"code": 0, "success": True,
            "data": {"publicKey": "MOCKPUBKEY", "keyId": "1", "sign": "mock"}}


def u_pin_code(q, body, d):
    return {"code": 0, "success": True, "data": {"pinVerifyCode": "mock-pvc", "expire": 300}}


def u_car_location(q, body, d):
    now = int(time.time())
    return {"code": 0, "success": True, "message": "ok", "data": {
        "lat": 29.5630, "lng": 106.5516,
        "latitude": 29.5630, "longitude": 106.5516,
        "address": "重庆市渝北区龙兴镇两江大道", "direction": 90,
        "speed": 0, "positionTime": now, "time": now,
        "carId": CAR["carId"],
    }}


def u_amap(q, body, d):
    return {"status": "1", "info": "OK", "data": {"count": "0", "evaluation": {}}}


ROUTES = {
    "/get_user_info": r_get_user_info,
    "/check_phone_exists": r_check_phone,
    "/get_code": r_get_code,
    "/register_user": r_register_user,
    "/save_token": r_save_token,
    "/encrypt_data": r_encrypt,
    "/api/real/online": r_real_online,
    "/api/real/cardetail": r_real_cardetail,
    "/api/real/unread": r_real_unread,
    "/api/real/location": r_real_location,
    "/api/auto/config": r_auto_config,
    "/api/real/energy": r_real_energy,
    "/api/real/report": r_real_report,
    "/api/real/maintenance": r_real_maintenance,
    "/api/real/checkitems": r_real_checkitems,
    "/api/oil/price": r_oil_price,
    "/api/real/balance": r_real_balance,
    "/api/real/profile": r_real_profile,
    "/api/real/sms": r_real_sms,
    "/api/real/session": r_real_session,
    "/api/real/login": r_real_login,
    "/api/real/token": r_real_token,
    "/api/real/status": r_real_status,
    "/get_scode": r_get_scode,
    "/api/auth/status": r_auth_status,
    "/api/auth/revoke": r_auth_revoke,
    "/api/usage/beat": r_usage_beat,
    "/api/ac/qrcode": r_ac_qrcode,
    "/api/ac/status": r_ac_status,
    "/api/open/token": r_open_token,
    "/api/open/login": r_ok,
    "/api/open/rotate": r_ok,
    "/api/siri/config": r_siri_config,
    "/api/siri/toggle": r_siri_toggle,
    "/api/siri/cmds": r_siri_cmds,
    "/api/siri/cars": r_siri_cars,
    "/api/siri/car": r_siri_car,
    "/api/siri/log": r_siri_log,
    "/api/siri/key/reset": r_siri_key_reset,
    "/api/siri/exec": r_siri_exec,
    "/api/club/list": r_club_list,
    "/api/club/post": r_club_post,
    "/api/club/like": r_club_like,
    "/api/club/comment": r_club_comment,
    "/api/club/view": r_club_view,
    "/api/club/delete": r_club_delete,
    "/api/club/upload": r_club_upload,
    "/api/fuel/log": r_fuel_log,
    "/api/fuel/delete": r_fuel_delete,
    "/agent/check": r_agent_check,
    "/agent/list": r_agent_list,
    "/agent/add": r_agent_add,
    "/agent/remove": r_agent_remove,
    "/admin/usage": r_admin_usage,
    "/admin/pass/init": r_admin_pass_init,
    "/admin/whitelist/init": r_admin_pass_init,
    "/admin/usage/block": r_admin_generic,
    "/admin/usage/unblock": r_admin_generic,
    "/admin/usage/delete": r_admin_generic,
    "/admin/admins/list": r_admin_admins_list,
    "/admin/admins/add": r_admin_admins_add,
    "/admin/admins/remove": r_admin_admins_remove,
    "/admin/admins/reset_pass": r_admin_generic,
    "/admin/wl/add": r_agent_add,
    "/admin/wl/remove": r_agent_remove,
    "/admin/wl/toggle": r_admin_generic,
    "/admin/is_admin": r_admin_is_admin,
    "/myth/check": r_myth_check,
    "/myth/wl_list": r_myth_wl_list,
    "/myth/wl_add": r_myth_wl_add,
    "/myth/wl_remove": r_myth_wl_remove,
    # 上游模拟
    "/mock/upstream/sms": u_sms,
    "/mock/upstream/oauth": u_register,
    "/mock/iov/incall/cac/api/v1/oauth2/refresh_token": u_oauth_refresh,
    "/mock/iov/m/app2/api/user/cars": u_cars,
    "/mock/iov/m/app2/api/car/data": u_car_data,
    "/mock/iov/m/app2/api/v3/control/execute": u_control,
    "/mock/iov/m/app2/api/v2/security/key": u_security_key,
    "/mock/iov/m/app2/api/control/createPinVerifyCode": u_pin_code,
    "/mock/iov/open/oauth/token": u_oauth_refresh,
    "/mock/iov/m/app2/api/car/location": u_car_location,
    "/mock/amap/v4/grasproad/driving": u_amap,
}


class Handler(SimpleHTTPRequestHandler):
    server_version = "ReplicaServer/1.0"
    protocol_version = "HTTP/1.0"   # 关闭 keep-alive：并发下连接复用会导致请求解析错位（501）

    def log_message(self, fmt, *args):
        pass

    def _log(self, method, path, status, note=""):
        try:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(f"{time.strftime('%H:%M:%S')} {status} {method} {path} {note}\n")
        except Exception:
            pass

    # ---------------- 工具
    def _raw_body(self):
        if getattr(self, "_raw_cache", None) is None:
            n = int(self.headers.get("Content-Length") or 0)
            self._raw_cache = self.rfile.read(n) if n else b""
        return self._raw_cache

    def _body(self):
        raw = self._raw_body()
        ctype = (self.headers.get("Content-Type") or "").lower()
        if not raw:
            return {}
        if "json" in ctype:
            try:
                return json.loads(raw.decode("utf-8", "replace") or "{}")
            except Exception:
                return {}
        if "x-www-form-urlencoded" in ctype:
            return {k: v[0] for k, v in urllib.parse.parse_qs(raw.decode("utf-8", "replace")).items()}
        # multipart 或纯文本
        try:
            return json.loads(raw.decode("utf-8", "replace"))
        except Exception:
            txt = raw.decode("utf-8", "replace")
            if "filename=" in txt:
                return {"_multipart": True}
            return {"_raw": txt}

    def send_error(self, code, message=None, explain=None):
        try:
            print("[HTTP-ERR] %s cmd=%r path=%r msg=%s" % (
                code, getattr(self, "command", None), getattr(self, "path", None), message), flush=True)
        except Exception:
            pass
        return BaseHTTPRequestHandler.send_error(self, code, message, explain)

    def _send(self, code, body, ctype="application/json; charset=utf-8", extra=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False)
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "same-origin")
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        try:
            self.wfile.write(body)
        except Exception:
            pass

    def _route_key(self, path):
        """去掉查询串，做前缀式匹配（/api/ac/status?x 之类已单独处理）"""
        p = urllib.parse.urlparse(path).path
        if p in ROUTES:
            return p
        for k in ROUTES:
            if k.startswith("/mock/") and p.startswith(k):
                return k
        return p

    def _dispatch(self, method):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # 真实上游代理：/real/iov/... /real/amap/...
        if path.startswith("/real/"):
            status, ctype, rbody = proxy_real(path, parsed.query, method,
                                              self._raw_body(), self.headers, load())
            self._log(method, path, status, "REAL")
            self._send(status, rbody, ctype)
            return

        q = urllib.parse.parse_qs(parsed.query)
        body = self._body() if method == "POST" else {}
        d = load()

        key = self._route_key(path)
        fn = ROUTES.get(key)
        if fn:
            ip = self.client_address[0]
            guarded = key == "/get_user_info" or path.startswith("/admin/")
            # 失败次数限流（防撞库）
            if guarded and not rate_ok(ip):
                self._log(method, path, 429, "RATE_LIMIT")
                self._send(429, {"success": False, "message": "尝试过于频繁，请 5 分钟后再试"})
                return
            # 管理接口必须携带正确管理密码
            if path.startswith("/admin/") and key not in ("/admin/pass/init", "/admin/is_admin"):
                _pw = body.get("password") or ""
                if not admin_ok(d, _pw):
                    if _pw:            # 只有真的输了错误密码才计入限流
                        rate_fail(ip)
                    self._log(method, path, 401, "ADMIN_AUTH")
                    # 前端约定：wrong_pass=true → 回到密码输入步骤，不回传任何数据
                    self._send(200, {"success": False, "wrong_pass": True,
                                     "message": "管理密码错误"})
                    return
            try:
                res = fn(q, body, d)
            except Exception as e:
                res = {"success": False, "message": f"复刻后端异常：{e}"}
            if key == "/get_user_info" and isinstance(res, dict) and res.get("success") is False:
                rate_fail(ip)
            self._log(method, path, 200)
            self._send(200, res)
            return

        # 未实现的自有接口：给个宽松的 ok，避免前端卡死
        if path.startswith(("/api/", "/admin/", "/agent/", "/myth/", "/mock/")):
            self._log(method, path, 200, "FALLBACK")
            self._send(200, {"success": True, "ok": True, "code": 0, "list": [],
                             "message": "ok（复刻兜底）"})
            return

        if method == "OPTIONS":
            self._send(204, b"")
            return

        # 页面路由
        if path in PAGE_ROUTES:
            self._serve_file(os.path.join(SITE, PAGE_ROUTES[path]), method)
            return
        if path.rstrip("/") in PAGE_ROUTES:
            self._serve_file(os.path.join(SITE, PAGE_ROUTES[path.rstrip("/")]), method)
            return

        # 静态
        rel = path.lstrip("/")
        full = os.path.normpath(os.path.join(SITE, rel))
        if full.startswith(SITE) and os.path.isfile(full):
            self._serve_file(full, method)
            return
        # /xxx → /xxx.html
        if os.path.isfile(full + ".html"):
            self._serve_file(full + ".html", method)
            return
        self._log(method, path, 404)
        self._send(404, {"success": False, "message": "Not Found"})

    def _serve_file(self, full, method):
        if not os.path.isfile(full):
            self._send(404, {"success": False, "message": "Not Found"})
            return
        ext = os.path.splitext(full)[1].lower()
        ctype = MIME.get(ext, "application/octet-stream")
        try:
            with open(full, "rb") as f:
                data = f.read()
        except Exception:
            self._send(500, {"success": False, "message": "read error"})
            return
        self._send(200, data, ctype)

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def do_PUT(self):
        self._dispatch("PUT")

    def do_DELETE(self):
        self._dispatch("DELETE")

    def do_PATCH(self):
        self._dispatch("PATCH")

    def do_HEAD(self):
        self._dispatch("HEAD")

    def do_OPTIONS(self):
        self._send(204, b"")

    def do_HEAD(self):
        self._send(200, b"")


def local_ips():
    """列出本机可用的局域网 IPv4，方便手机扫码/输地址访问"""
    ips = []
    try:
        import socket
        host = socket.gethostname()
        for info in socket.getaddrinfo(host, None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    if not ips:
        try:
            import socket
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ips.append(s.getsockname()[0])
            s.close()
        except Exception:
            pass
    return ips


AUTO_GUARD_SEC = 900   # 每 15 分钟检查一次


def _bark_push(key, title, body):
    if not key:
        return
    try:
        url = ("https://api.day.app/" + key + "/" +
               urllib.parse.quote(title) + "/" + urllib.parse.quote(body) + "?group=car")
        urllib.request.urlopen(url, timeout=10).read()
    except Exception:
        pass


def _auto_close_windows(cfg, d):
    """熄火 + 车窗未关 → 远程关窗并 Bark 推送"""
    phone, at, cid = _real_ctx({}, {}, d)
    if not at or not cid:
        return
    HDR = "https://m.iov.changan.com.cn"
    try:
        st = _car_data(at, cid)
    except Exception:
        return
    wins = {
        "主驾": st.get("leftFrontDoorrWindow"),
        "副驾": st.get("rightFrontDoorrWindow"),
        "左后": st.get("leftRearWindow"),
        "右后": st.get("rightRearWindow"),
    }
    opened = [k for k, v in wins.items() if str(v) == "1"]
    if not opened:
        if cfg.get("last_sig"):
            with LOCK:
                d.setdefault("auto_close", {})["last_sig"] = ""
                save(d)
        return
    if str(st.get("engineStatus")) != "2":
        return
    sig = ",".join(opened)
    if cfg.get("last_sig") == sig:
        return

    ok = False
    detail = ""
    try:
        pv = changan_post(HDR + "/app2/api/control/createPinVerifyCode?carId=" + urllib.parse.quote(cid)
                          + "&token=" + urllib.parse.quote(at) + "&isNev=0", {})
        code = pv.get("data") or ""
        pub = changan_get(HDR + "/app2/api/v2/security/key?carId=" + urllib.parse.quote(cid)
                          + "&token=" + urllib.parse.quote(at)).get("data") or ""
        pt = json.dumps({"cmd": "CloseWindow", "type": "CloseWindow",
                         "pin": cfg.get("pin") or "", "pinVerifyCode": code}, ensure_ascii=False)
        cipher = rsa_enc.encrypt_oaep(pub, pt, "sha256")
        r = changan_post(HDR + "/app2/api/v3/control/execute",
                         {"carId": cid, "token": at, "isNev": 0, "s": cipher})
        ok = bool(r.get("success"))
        detail = r.get("msg") or ""
    except Exception as e:
        detail = str(e)[:80]

    _bark_push(cfg.get("bark_key") or ("已自动关窗" if ok else "车窗未关"),
               "已自动关窗" if ok else "车窗未关",
               "检测到 " + "、".join(opened) + " 窗未关，" +
               ("已远程关闭" if ok else ("自动关闭失败：" + (detail or "请手动处理"))))
    with LOCK:
        ac = d.setdefault("auto_close", {})
        ac["last_sig"] = sig
        ac["last_time"] = int(time.time())
        ac["last_ok"] = ok
        save(d)


def _guard_alerts(st, cfg, d):
    """胎压 / 油量 / 电压 / 熄火后开门 / 保养到期 / 每日早报"""
    ac = d.setdefault("auto_close", {})
    fired = ac.setdefault("fired", {})
    key = cfg.get("bark_key") or ""
    now = time.time()
    msgs = []

    # 1) 胎压异常
    tys = {"左前": st.get("lfTyrePressure"), "右前": st.get("rfTyrePressure"),
           "左后": st.get("lrTyrePressure"), "右后": st.get("rrTyrePressure")}
    bad = [(n, v) for n, v in tys.items() if v not in (None, "", "-1") and (float(v) < 200 or float(v) > 280)]
    warn = any(str(st.get(k)) == "1" for k in ("lfPressureWarning", "rfPressureWarning",
                                               "lrPressureWarning", "rrPressureWarning"))
    if bad or warn:
        sig = "tyre:" + ",".join(f"{n}{int(v)}" for n, v in bad)
        if fired.get("tyre") != sig:
            detail = "、".join(f"{n} {int(v)}kPa" for n, v in bad) or "胎压报警灯亮"
            msgs.append(("胎压异常", detail))
            fired["tyre"] = sig
    elif fired.get("tyre"):
        fired["tyre"] = ""

    # 2) 低油量
    try:
        fl = float(st.get("fuelLeftover") or -1)
        rm = float(st.get("remainedOilMile") or -1)
    except Exception:
        fl = rm = -1
    if 0 <= fl <= 10 or 0 <= rm <= 80:
        sig = f"fuel:{int(fl)}:{int(rm)}"
        if fired.get("fuel") != sig:
            msgs.append(("油量偏低", f"剩余 {fl:.0f} L，续航 {rm:.0f} km"))
            fired["fuel"] = sig
    elif fired.get("fuel"):
        fired["fuel"] = ""

    # 3) 电瓶电压低
    try:
        bv = float(st.get("batteryVoltage") or -1)
    except Exception:
        bv = -1
    if 0 < bv < 11.8:
        if fired.get("volt") != "low":
            msgs.append(("电瓶电压低", f"{bv} V，建议尽快检查或补电"))
            fired["volt"] = "low"
    elif fired.get("volt"):
        fired["volt"] = ""

    # 4) 熄火后车门被打开（防盗）
    engine_off = str(st.get("engineStatus")) == "2"
    opened = [n for n, k in (("主驾", "leftFrontDoor"), ("副驾", "rightFrontDoor"),
                             ("左后", "leftRearDoor"), ("右后", "rightRearDoor"))
              if str(st.get(k)) == "1"]
    if engine_off and opened:
        sig = "door:" + ",".join(opened)
        if fired.get("door") != sig:
            msgs.append(("车门被打开", "熄火状态下 " + "、".join(opened) + " 门打开，注意防盗"))
            fired["door"] = sig
    elif fired.get("door"):
        fired["door"] = ""

    # 5) 保养到期（剩余 <10%）
    try:
        j = changan_get("https://m.iov.changan.com.cn/mt/uc/api/maintenance/next?carId="
                        + urllib.parse.quote(_real_ctx({}, {}, d)[2]) + "&appVersion=3.2.0&token="
                        + urllib.parse.quote(_real_ctx({}, {}, d)[1]))
        due = [a.get("maintenanceName") for a in ((j.get("data") or {}).get("advices") or [])
               if a.get("remainPercentage") is not None and float(a["remainPercentage"]) < 10]
        if due:
            sig = "maint:" + ",".join(due)
            if fired.get("maint") != sig:
                msgs.append(("保养到期", "、".join(due) + " 剩余不足 10%，建议尽快预约保养"))
                fired["maint"] = sig
        elif fired.get("maint"):
            fired["maint"] = ""
    except Exception:
        pass

    # 6) 每日早报 08:00
    lt = time.localtime(now)
    today = time.strftime("%Y%m%d", lt)
    if lt.tm_hour == 8 and fired.get("daily") != today:
        try:
            pct = round(fl / 53 * 100) if fl > 0 else 0
            msgs.append(("今日车况", f"油量 {fl:.0f}L（{pct}%）· 续航 {rm:.0f}km · 电压 {bv}V"))
            fired["daily"] = today
        except Exception:
            pass

    # 7) 油量跳变 → 自动记一次加油
    try:
        fl_now = float(st.get("fuelLeftover") or 0)
        odo_now = float(st.get("totalOdometer") or st.get("totalMileage") or 0)
        last_fuel = ac.get("last_fuel")
        if last_fuel is not None and odo_now > 0 and fl_now - float(last_fuel) >= 10:
            liters = round(fl_now - float(last_fuel), 1)
            price = float((d.get("oil_cache") or {}).get("p92") or 8.98)
            prev_odo = ac.get("last_odo")
            dist = round(odo_now - float(prev_odo), 1) if prev_odo else None
            rec = {"id": int(now), "date": time.strftime("%Y-%m-%d"), "ts": int(now),
                   "odo": round(odo_now, 1), "liters": liters, "price": price,
                   "amount": round(liters * price, 2),
                   "per100": round(liters / dist * 100, 1) if dist and dist > 0 else None,
                   "distance": dist, "full": True, "auto": True}
            _ph2, _at2, _cid2 = _real_ctx({}, {}, d)
            with LOCK:
                d.setdefault("fuel", {}).setdefault(_ph2 or "", []).append(rec)
                ac["last_fuel"] = fl_now
                ac["last_odo"] = odo_now
                save(d)
            _bark_push(key, "检测到加油", f"约 {liters} L · {rec['odo']} km，已自动记账")
        elif last_fuel is None and fl_now > 0:
            ac["last_fuel"] = fl_now
            if odo_now > 0:
                ac["last_odo"] = odo_now
    except Exception:
        pass

    for title, body in msgs:
        _bark_push(key, title, body)

    if msgs:
        with LOCK:
            ac["last_alert"] = int(now)
            save(d)


def auto_guard_loop():
    while True:
        time.sleep(AUTO_GUARD_SEC)
        try:
            d = load()
            cfg = d.get("auto_close") or {}
            if cfg.get("enabled") and cfg.get("pin"):
                _auto_close_windows(cfg, d)
            # 定时锁车
            at_time = (cfg.get("auto_lock_at") or "").strip()
            if cfg.get("enabled") and at_time:
                now_hm = time.strftime("%H:%M")
                today = time.strftime("%Y%m%d")
                if now_hm == at_time and cfg.get("lock_done") != today:
                    r = _do_cmd("LockDoor")
                    _bark_push(cfg.get("bark_key") or "", "定时锁车",
                               "已自动锁车" if r.get("success") else ("锁车失败：" + (r.get("message") or "")))
                    with LOCK:
                        d.setdefault("auto_close", {})["lock_done"] = today
                        save(d)

            if cfg.get("enabled") and cfg.get("bark_key"):
                try:
                    _ph, _at, _cid = _real_ctx({}, {}, d)
                    if _at and _cid:
                        _st = _car_data(_at, _cid)
                        if _st:
                            _guard_alerts(_st, cfg, d)
                except Exception:
                    pass
        except Exception:
            pass


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    port = int(args[0]) if args else 8080
    host = os.environ.get("HOST", "0.0.0.0")   # 0.0.0.0 = 同一 WiFi 下手机也能访问
    if not os.path.isdir(SITE):
        print("缺少 site/ 目录，先运行： python build.py")
        sys.exit(1)
    threading.Thread(target=auto_guard_loop, daemon=True).start()
    srv = ThreadingHTTPServer((host, port), Handler)
    print("=" * 56)
    print("  远程控车系统 · 复刻版（卡密已移除）")
    print(f"  本机：http://127.0.0.1:{port}")
    if host in ("0.0.0.0", ""):
        for ip in local_ips():
            print(f"  手机（同一 WiFi）：http://{ip}:{port}")
    print(f"  演示账号：{DEMO_PHONE}   控车码：{DEMO_PIN}")
    print(f"  管理密码：{ADMIN_PASS}")
    print(f"  数据文件：{DATA_FILE}")
    print("=" * 56)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    main()
