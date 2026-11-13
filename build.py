#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把抓下来的 _dump/ 组装成可运行的 site/，并注入复刻用 shim。"""
import os, re, shutil
import strip_card
import strip_notice
import patch_login

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "_dump")
DST = os.path.join(HERE, "site")

SKIP_DIRS = {"api", "_report.json"}
SKIP_FILES = {"_report.json"}


REAL_PAGE = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "real_page.html"), encoding="utf-8").read()

PAGES = {
    "index.html": "/",
    "user_info.html": "/user_info",
    "vehicle_status.html": "/vehicle_status",
    "guide.html": "/guide",
    "real.html": "/real",
}


def main():
    if os.path.isdir(DST):
        shutil.rmtree(DST)
    os.makedirs(DST)

    for root, dirs, files in os.walk(SRC):
        rel = os.path.relpath(root, SRC)
        if rel == ".":
            rel = ""
        parts = rel.split(os.sep) if rel else []
        if parts and parts[0] in SKIP_DIRS:
            continue
        for f in files:
            if f in SKIP_FILES:
                continue
            src = os.path.join(root, f)
            dst = os.path.join(DST, rel, f) if rel else os.path.join(DST, f)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)

    # 复制 shim
    shutil.copy2(os.path.join(HERE, "replica_shim.js"), os.path.join(DST, "replica_shim.js"))

    # 修补：原站 vehicle_status.html 的服务端渲染占位块（无参数时无条件报错）
    # 镜像下来后会一直显示「缺少必要参数」，改成按真实参数条件判断。
    vs = os.path.join(DST, "vehicle_status.html")
    if os.path.exists(vs):
        t = open(vs, encoding="utf-8", errors="replace").read()
        old = """        document.getElementById('phoneDisplay').textContent = maskPhone('');


        document.getElementById('error-message').classList.remove('hidden');
        document.getElementById('error-text').textContent = '缺少必要参数: 手机号, ref_token, pin';
        document.getElementById('loading-container').classList.add('hidden');
        document.getElementById('vehicleStatus').classList.remove('hidden');"""
        new = """        /* [复刻补丁] 原为服务端渲染占位，改为按真实参数判断 */
        (function () {
            var _q = new URLSearchParams(location.search);
            var _ph = _q.get('phone') || localStorage.getItem('phone') || '';
            document.getElementById('phoneDisplay').textContent = maskPhone(_ph);
            if (!_ph) {
                document.getElementById('error-message').classList.remove('hidden');
                document.getElementById('error-text').textContent = '缺少必要参数: 手机号';
                document.getElementById('loading-container').classList.add('hidden');
                document.getElementById('vehicleStatus').classList.remove('hidden');
            }
        })();"""
        if old in t:
            t = t.replace(old, new)
            print("已修补 vehicle_status.html 的参数占位块")

        # 原站由服务端把凭证写进 hidden input，镜像后为空 → 这里用 URL/localStorage 回填
        anchor = '<script src="../static/js/car_fields.js"></script>'
        filler = """<script>
    /* [复刻补丁] 原由服务端模板注入凭证，改为前端回填 */
    (function () {
        var q = new URLSearchParams(location.search);
        function pick(k) { return q.get(k) || localStorage.getItem(k) || ''; }
        var set = function (id, v) { var e = document.getElementById(id); if (e) e.value = v; };
        set('refTokenInput', pick('ref_token'));
        set('pinInput', pick('pin'));
        var _p = document.getElementById('phoneDisplay');
        if (_p && pick('phone')) _p.textContent = pick('phone').replace(/^(\\d{3})\\d{4}(\\d{4})$/, '$1****$2');
    })();
    </script>
    """ + anchor
        if anchor in t and "[复刻补丁] 原由服务端模板注入凭证" not in t:
            t = t.replace(anchor, filler, 1)
            print("已回填 vehicle_status.html 凭证隐藏域")
        open(vs, "w", encoding="utf-8").write(t)

    # 真实车辆接入页
    open(os.path.join(DST, "real.html"), "w", encoding="utf-8").write(REAL_PAGE)

    # 使用说明页：替换原站那份含卡密说明的 guide
    _gp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "guide_page.html")
    if os.path.exists(_gp):
        open(os.path.join(DST, "guide.html"), "w", encoding="utf-8").write(
            open(_gp, encoding="utf-8").read())

    # 物理删除卡密系统（DOM + JS，不是隐藏）
    p_index = os.path.join(DST, "index.html")
    p_user = os.path.join(DST, "user_info.html")
    p_vs = os.path.join(DST, "vehicle_status.html")
    p_vsj = os.path.join(DST, "static", "js", "vehicle_status.js")
    idx = open(p_index, encoding="utf-8", errors="replace").read()
    usr = open(p_user, encoding="utf-8", errors="replace").read()
    vs = open(p_vs, encoding="utf-8", errors="replace").read()
    vsj = open(p_vsj, encoding="utf-8", errors="replace").read()
    idx, usr, vs, vsj, ops = strip_card.apply(idx, usr, vs, vsj)
    # 车型图换成官网 UNI-V 透明渲染图（png）
    _b3 = usr
    usr = usr.replace("static/img/univ_side.webp?v=1", "static/img/univ_side.png?v=3")
    usr = usr.replace("static/img/univ_top.png'", "static/img/univ_top.png?v=3'")
    print("  UNI-V 车图换官方图：" + ("OK" if usr != _b3 else "FAIL"))

    # 「更新于」用车辆上报时间（terminalTime），不是浏览器当前时间
    _b4 = usr
    usr = usr.replace("""                var tEl = document.getElementById('updateTime');
                if (tEl) {
                    var d = new Date();
                    var p = function (n) { return (n < 10 ? '0' : '') + n; };
                    tEl.textContent = p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
                }""",
"""                var tEl = document.getElementById('updateTime');
                if (tEl) {
                    var tt2 = (window.__terminalTime || '');
                    var p = function (n) { return (n < 10 ? '0' : '') + n; };
                    tEl.textContent = tt2 ? String(tt2).slice(11, 19)
                        : (p(new Date().getHours()) + ':' + p(new Date().getMinutes()) + ':' + p(new Date().getSeconds()));
                }""", 1)
    print("  更新时间改终端时间：" + ("OK" if usr != _b4 else "FAIL"))

    # 加油表单：改单价应算金额，原逻辑反着来会覆盖用户输入的油价
    _b5 = usr
    usr = usr.replace("""            if (changed === 'price' && lOk && aOk) document.getElementById('fPrice').value = fmt2(A / L);
            else if (changed === 'liters' && pOk && aOk) document.getElementById('fLiters').value = fmt2(A / P);
            else if (changed === 'amount' && pOk && lOk) document.getElementById('fAmount').value = fmt2(P * L);""",
"""            if (changed === 'price' && lOk) document.getElementById('fAmount').value = fmt2(P * L);
            else if (changed === 'liters' && pOk) document.getElementById('fAmount').value = fmt2(P * L);
            else if (changed === 'amount' && lOk) document.getElementById('fPrice').value = fmt2(A / L);""", 1)
    print("  加油表单单价联动修正：" + ("OK" if usr != _b5 else "FAIL"))

    # 真实模式下跳过原站的模拟账号校验（否则会误报「账号不存在」）
    _b2 = usr
    usr = usr.replace("function _authCheck() {",
                      "function _authCheck() {\n            if (localStorage.getItem('replica_real_upstream') === '1') return;", 1)
    print("  跳过模拟账号校验：" + ("OK" if usr != _b2 else "FAIL"))

    # 空调等「官方版」入口依赖 open 平台独立 token，统一改走车机接口（与闭锁同一条链路）
    _before = usr
    usr = usr.replace("var isNew = mode === 'new';",
                      "var isNew = false;  // 统一走车机接口", 1)
    print("  空调改车机接口：" + ("OK" if usr != _before else "FAIL"))

    open(p_index, "w", encoding="utf-8").write(idx)
    open(p_user, "w", encoding="utf-8").write(usr)
    open(p_vs, "w", encoding="utf-8").write(vs)
    open(p_vsj, "w", encoding="utf-8").write(vsj)
    bad = [n for n, ok in ops if not ok]
    print(f"卡密清理：{len(ops)} 项操作完成" + (f"，失败 {len(bad)} 项：{bad}" if bad else "，全部成功"))

    # 去掉原站的 QQ / 公告 / 招募等营销信息
    idx = open(p_index, encoding="utf-8", errors="replace").read()
    usr = open(p_user, encoding="utf-8", errors="replace").read()
    idx, usr, ops2 = strip_notice.apply(idx, usr)

    # 登录页短信登录 → 真实长安接口
    idx, ops3 = patch_login.apply(idx)
    for n, ok in ops3:
        print(("  登录改造 OK   " if ok else "  登录改造 FAIL ") + n)

    # 登录页加「真实登录」入口：手机号 + 官方短信验证码
    _entry = (
        '\n                <a href="/real" style="display:flex;align-items:center;justify-content:center;'
        'gap:7px;margin-top:12px;padding:12px;border-radius:12px;'
        'background:linear-gradient(135deg,#ff5a52,#ef4444);color:#fff;font-size:14px;'
        'font-weight:600;text-decoration:none;box-shadow:0 8px 22px rgba(255,90,82,.28)">'
        '用车联网账号登录 · 真实控车</a>'
        '\n                <p style="margin:8px 0 0;font-size:11px;text-align:center;color:var(--muted)">'
        '收一条长安官方短信验证码即可进入，无需控车码</p>\n'
    )
    if 'href="/real"' not in idx:
        _anchor = '                </form>\n            </div>'
        if _anchor in idx:
            idx = idx.replace(_anchor, '                </form>\n' + _entry + '            </div>', 1)

    open(p_index, "w", encoding="utf-8").write(idx)
    open(p_user, "w", encoding="utf-8").write(usr)
    bad2 = [n for n, ok in ops2 if not ok]
    print(f"公告/QQ 清理：{len(ops2)} 项操作完成" + (f"，失败 {len(bad2)} 项：{bad2}" if bad2 else "，全部成功"))

    # 注入 shim + 去掉卡密入口
    shim = '<script src="/replica_shim.js?v=1"></script>\n'
    
    n = 0
    for name in PAGES:
        p = os.path.join(DST, name)
        if not os.path.exists(p):
            continue
        t = open(p, encoding="utf-8", errors="replace").read()
        if "replica_shim.js" in t:
            continue
        m = re.search(r"<head[^>]*>", t, re.I)
        if m:
            t = t[: m.end()] + "\n" + shim + t[m.end():]
        else:
            t = shim + t
        open(p, "w", encoding="utf-8").write(t)
        n += 1
    print(f"site/ 组装完成，注入 shim 的页面：{n}")
    total = sum(len(fs) for _, _, fs in os.walk(DST))
    print(f"文件总数：{total}")


if __name__ == "__main__":
    main()
