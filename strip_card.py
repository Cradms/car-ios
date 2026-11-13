#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""卡密系统清理器（物理删除，不是隐藏）

把原站「卡密 / 体验卡 / 永久卡 / 体验模式」整套逻辑从镜像页面里删干净：
 - DOM：登录页卡密弹窗、体验卡管理区、永久卡区、体验版升级弹层、体验版角标、我的页卡密入口
 - JS：卡密生成/列表/复制/作废/删除/校验、体验模式限制与定时复查、入口初始化、死代码
 - 保留与卡密无关的功能：管理员任命、白名单、代理管理、使用统计

外加：永久卡弹层保留「管理员任命」，改为普通的管理员管理弹层。

由 build.py 在组装 site/ 之后调用。
"""
import re

# ---------------------------------------------------------------- 基础工具


def _skip_string(s, i):
    q = s[i]
    i += 1
    while i < len(s):
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == q:
            return i + 1
        i += 1
    return i


def find_matching_brace(s, open_idx):
    depth = 0
    i, n = open_idx, len(s)
    while i < n:
        c = s[i]
        if c in "\"'`":
            i = _skip_string(s, i)
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            j = s.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def remove_function(js, name):
    pats = [
        r"\n[ \t]*function\s+%s\s*\([^)]*\)\s*\{" % re.escape(name),
        r"\n[ \t]*window\.%s\s*=\s*function\s*\([^)]*\)\s*\{" % re.escape(name),
        r"\n[ \t]*var\s+%s\s*=\s*function\s*\([^)]*\)\s*\{" % re.escape(name),
        r"\n[ \t]*%s\s*=\s*function\s*\([^)]*\)\s*\{" % re.escape(name),
    ]
    removed = 0
    for p in pats:
        while True:
            m = re.search(p, js)
            if not m:
                break
            brace = js.index("{", m.start())
            end = find_matching_brace(js, brace)
            if end < 0:
                break
            end += 1
            while end < len(js) and js[end] in " \t":
                end += 1
            if end < len(js) and js[end] == ";":
                end += 1
            while end < len(js) and js[end] in "\r\n" and not js.startswith("\r\n\r\n", end):
                end += 1
            js = js[:m.start()] + "\n" + js[end:]
            removed += 1
    return js, removed


def remove_element(html, elem_id):
    m = re.search(r"<([a-zA-Z][\w-]*)\b[^>]*\bid=[\"']%s[\"']" % re.escape(elem_id), html)
    if not m:
        return html, False
    tag = m.group(1)
    start = m.start()
    open_end = html.find(">", m.end())
    depth = 1
    i = open_end + 1
    open_re = re.compile(r"<%s\b" % re.escape(tag), re.I)
    close_re = re.compile(r"</%s\s*>" % re.escape(tag), re.I)
    while i < len(html) and depth > 0:
        no = open_re.search(html, i)
        nc = close_re.search(html, i)
        if not nc:
            return html, False
        if no and no.start() < nc.start():
            depth += 1
            i = no.end()
        else:
            depth -= 1
            i = nc.end()
    line_start = html.rfind("\n", 0, start) + 1
    if html[line_start:start].strip() == "":
        start = line_start
        prev_start = html.rfind("\n", 0, start - 1) + 1
        prev_line = html[prev_start:start].strip()
        if prev_line.startswith("<!--") and prev_line.endswith("-->"):
            start = prev_start
    end = i
    while end < len(html) and html[end] in "\r\n":
        end += 1
    return html[:start] + html[end:], True


def cut_between(text, start_anchor, end_anchor, keep_end=True):
    a = text.find(start_anchor)
    if a < 0:
        return text, False
    b = text.find(end_anchor, a + len(start_anchor))
    if b < 0:
        return text, False
    return text[:a] + (text[b:] if keep_end else text[b + len(end_anchor):]), True


def drop_lines(text, *needles):
    """删掉包含任一关键字的整行（只用于注释/死代码行）"""
    out, n = [], 0
    for line in text.split("\n"):
        if any(k in line for k in needles):
            n += 1
            continue
        out.append(line)
    return "\n".join(out), n


# ---------------------------------------------------------------- index.html


def strip_index(html):
    log = []

    html, ok = remove_element(html, "cardModal")
    log.append(("index: 删除 #cardModal 弹窗", ok))

    html, ok = cut_between(
        html,
        "        function openCardCheckOrGo(phone, ref, pin) {",
        "        function copyOwnerQQ() {",
    )
    log.append(("index: 删除卡密全套函数（校验/弹窗/提交）", ok))

    html, ok = cut_between(
        html,
        "        function backToLogin() {",
        "    </script>",
    )
    log.append(("index: 删除卡密弹窗的返回逻辑 backToLogin", ok))

    html = re.sub(r"\n[ \t]*var PENDING[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*/\* =+ 卡密校验[^\n]*", "", html)
    html = html.replace("if (!data) return;   // 卡密分支：弹窗已处理，中断链",
                        "if (!data) return;")

    for old, new in [
        ("openCardCheckOrGo(phone, data.ref_token, data.pin);",
         "goUserInfo(phone, data.ref_token, data.pin);"),
        ("openCardCheckOrGo(mobile, savedRefreshToken, pin);",
         "goUserInfo(mobile, savedRefreshToken, pin);"),
    ]:
        html = html.replace(old, new)

    # 获取验证码前的「未授权 → 弹卡密」分支
    m = re.search(
        r"\n[ \t]*// 未获授权（白名单外）[^\n]*\n[ \t]*if \(data\.unauthorized === true\) \{[\s\S]*?\n[ \t]*\}\n",
        html)
    log.append(("index: 删除未授权弹卡密分支", bool(m)))
    if m:
        html = html[:m.start()] + "\n" + html[m.end():]

    return html, log


# ---------------------------------------------------------------- user_info.html

CARD_FUNCS = [
    "cardGenerate", "cardCopyNew", "cardCopy", "cardVoid", "cardDelete", "cardLoad",
    "_renderCardPage", "cardNav", "cardRefresh",
    "openPermUpgradeModal", "closePermUpgradeModal", "submitPermUpgrade",
    "permCardLoad", "permCardGenerate", "permCardCopyNew", "_renderPermCardPage",
    "permCardNav", "permCardVoid", "permCardDelete",
    "permCardEntryInit", "checkExperienceMode", "_applyExpRestrictions",
]

CARD_ELEMS = [
    "expModeChip", "permCardEntryBox", "cardBox", "permUpgradeModal",
    "permCardSummary", "permCardNewResult", "permCardListBox", "permCardPager",
    "permCardNote", "permCardCount", "cardGenRow",
]


def strip_user_info(html):
    log = []

    html, ok = cut_between(
        html,
        "        // ===== 体验模式（卡密授权）",
        "        function closeModal() {",
    )
    log.append(("user: 删除体验模式整块（限制 + 定时复查 + 首调）", ok))

    html, ok = cut_between(
        html,
        "            /* 体验模式：拦截进入受限页面",
        "            })();\n",
        keep_end=False,
    )
    log.append(("user: 删除 tabGo 体验版拦截", ok))

    for name in CARD_FUNCS:
        html, n = remove_function(html, name)
        if n:
            log.append((f"user: 删除函数 {name}()", True))
        html = re.sub(r"\n[ \t]*window\.%s\s*=\s*%s\s*;[ \t]*" % (re.escape(name), re.escape(name)), "", html)

    for eid in CARD_ELEMS:
        html, ok = remove_element(html, eid)
        if ok:
            log.append((f"user: 删除 #{eid}", True))

    # 永久卡弹层：摘掉卡密生成区与卡密列表，保留管理员任命
    html, ok1 = cut_between(html,
                            "                    <!-- 正式版卡密生成 -->",
                            "                    <!-- 管理员任命 -->")
    html, ok2 = cut_between(html,
                            "                    <!-- 永久卡列表 -->",
                            "                </div>\n            </div>\n        </div>\n    </div>")
    log.append(("user: 永久卡弹层摘除卡密区（保留管理员任命）", ok1 and ok2))

    # 弹层改名 + 密码校验改走 /admin/usage
    for old, new in [
        ('<div id="permCardModal"', '<div id="adminMgmtModal"'),
        ('id="permCardLoginStep"', 'id="adminMgmtLoginStep"'),
        ('id="permCardPass"', 'id="adminMgmtPass"'),
        ('id="permCardMainBox"', 'id="adminMgmtMainBox"'),
        ('onclick="permCardLogin()"', 'onclick="adminMgmtLogin()"'),
        ('window.permCardLogin = function () {', 'window.adminMgmtLogin = function () {'),
        ("getElementById('permCardPass')", "getElementById('adminMgmtPass')"),
        ("getElementById('permCardLoginStep')", "getElementById('adminMgmtLoginStep')"),
        ("getElementById('permCardMainBox')", "getElementById('adminMgmtMainBox')"),
        ("getElementById('permCardModal')", "getElementById('adminMgmtModal')"),
        ("onclick=\"openPermCardSheet()\"", "onclick=\"openAdminMgmtSheet()\""),
        ("window.openPermCardSheet = function () {", "window.openAdminMgmtSheet = function () {"),
        ("window.closePermCardSheet = function () {", "window.closeAdminMgmtSheet = function () {"),
        ("openPermCardSheet()", "openAdminMgmtSheet()"),
        ("closePermCardSheet()", "closeAdminMgmtSheet()"),
        ("permanent: card_type", "permanent: card_type"),
        ("}>永久卡卡密</span>", ">管理员管理</span>"),
        (">永久卡卡密<", ">管理员管理<"),
        (">\n                    永久卡卡密\n                <", ">\n                    管理员管理\n                <"),
        ("永久卡卡密弹层（仅站主可见）", "管理员管理弹层（仅站主可见）"),
        ("请输入管理密码以管理正式版卡密与管理员。", "请输入管理密码以管理管理员。"),
        ("permCardLoad(); permAdminLoad();", "permAdminLoad();"),
    ]:
        html = html.replace(old, new)

    # 「我的」页入口改造成管理员管理入口（原为永久卡卡密入口）
    html = html.replace('<div id="permCardEntryRow" class="me-row hidden" onclick="openAdminMgmtSheet()">',
                        '<div id="permCardEntryRow" class="me-row" onclick="openAdminMgmtSheet()">')
    html = html.replace('<p class="text-[13px] font-semibold">永久卡卡密</p>',
                        '<p class="text-[13px] font-semibold">\u7ba1\u7406\u5458\u7ba1\u7406</p>')
    html = html.replace('正式版卡密（永久使用）· 站主与管理员',
                        '\u4efb\u547d\u7ba1\u7406\u5458 · \u4ec5\u7ad9\u4e3b')

    # 密码校验：原来借 /admin/card/list 验证，改为 /admin/usage
    html = html.replace("""            fetch('/admin/card/list', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ password: p, caller: currentPhone(), scope: 'permanent' })
            }).then(function (r) { return r.json(); }).then(function (res) {
                if (!res.success) { alert(res.message || '验证失败'); return; }
                if (res.not_owner) { alert('永久卡区仅站主可见'); closeAdminMgmtSheet(); return; }""",
    """            fetch('/admin/usage', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ password: p, caller: currentPhone() })
            }).then(function (r) { return r.json(); }).then(function (res) {
                if (!res.success) { alert(res.message || '验证失败'); return; }
                if (!res.is_owner) { alert('仅站主可见'); closeAdminMgmtSheet(); return; }""")

    # 使用统计面板里的卡密死代码
    html = re.sub(r"\n[ \t]*// 区块权限：[^\n]*", "\n            // 区块权限：白名单开关仅站主可拨动，白名单区站主/代理可见", html)
    html = re.sub(r"\n[ \t]*var cbox = document\.getElementById\('cardBox'\);[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*var pbox = document\.getElementById\('permCardEntryBox'\);[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*if \(pbox\)[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*if \(cbox\) \{[\s\S]{0,500}?\n[ \t]*\}\n", "\n", html, count=1)
    html = re.sub(r"\n[ \t]*// ===== 体验卡密管理[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*// ===== 体验用户升级正式卡[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*// ===== 永久卡卡密区[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*/\* 体验版保留「车辆状态」[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*/\*[^\n]*体验版[^\n]*\*/", "", html)
    html = html.replace("' · 名下体验卡 ' + a.card_count + ' · '", "' · '")
    html = re.sub(r"\n[ \t]*/\* 永久卡卡密入口[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*window\.permCardEntryInit = permCardEntryInit;[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*document\.addEventListener\('DOMContentLoaded', permCardEntryInit\);", "", html)
    html = re.sub(r"\n[ \t]*permCardEntryInit\(\);", "", html)
    html = re.sub(r"\n[ \t]*if \(typeof window\._permCardPage === 'undefined'\)[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*if \(typeof window\._cardPage === 'undefined'\)[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*window\._cardToday[^\n]*", "", html)

    # 残留文案
    html = html.replace(
        "使用统计（只读）· 体验卡密 · 白名单授权</b>。不可使用：永久卡、管理员任命、强制下线、拉黑。",
        "使用统计（只读）· 白名单授权</b>。不可使用：管理员任命、强制下线、拉黑。")
    html = html.replace("再次登录需要重新获得白名单或卡密授权", "再次登录需要重新获得白名单授权")
    html = re.sub(r"、\s*卡密到期", "", html)
    html = re.sub(r",\s*'体验版权限收紧为仅控车页[^']*'", "", html)
    html = html.replace("（仅手机号与用户类型：白名单 / 永久卡 / 体验）",
                        "（仅手机号与用户类型：白名单 / 管理员）")
    html = html.replace("// 有效代理：只读统计 + 体验卡 + 白名单（无开关/黑名单/永久卡）",
                        "// 有效代理：只读统计 + 白名单（无开关/黑名单）")
    html = html.replace("/* 管理员名单（永久卡区独立面板", "/* 管理员名单（管理员管理面板")
    html = html.replace("（移出白名单 / 卡密到期 / 被拉黑 / 被强退）", "（移出白名单 / 被拉黑 / 被强退）")
    html = html.replace("可使用【体验卡密】与【白名单管理】功能", "可使用【白名单管理】功能")
    # 使用统计摘要里的卡密口径
    html = html.replace(
        " + (opts.people_wl || 0) + ' · 永久 ' + (opts.people_perm || 0) + ' · 体验 ' + (opts.people_exp || 0) + ",
        " + (opts.people_wl || 0) + ")
    # 用户明细里的身份徽标：去掉「正式 / 体验 / 未授权」这些卡密态
    html = re.sub(r"\n[ \t]*else if \(u\.permanent\)[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*else if \(u\.card === 'ok'\)[^\n]*", "", html)
    html = re.sub(r"\n[ \t]*else if \(u\.card === 'unauth' \|\| u\.card === 'expired'\)[^\n]*", "", html)
    html = html.replace("// 身份标签优先级：站主 > 管理员 > 正式 > 白名单 > 体验 > 未授权",
                        "// 身份标签优先级：站主 > 管理员 > 白名单 > 普通用户")
    html = html.replace(
        'border:1px solid #fecaca;border-radius:8px;padding:1px 7px;font-size:10px;font-weight:600">未授权</span>',
        'border:1px solid #e2e8f0;border-radius:8px;padding:1px 7px;font-size:10px;font-weight:600">普通用户</span>')

    return html, log


# ---------------------------------------------------------------- vehicle_status


def strip_vehicle_status(html, js):
    log = []

    html, ok = cut_between(
        html,
        "        /* 体验版（卡密授权）：隐藏油耗记录卡",
        "        loadFuelLog();",
    )
    log.append(("vehicle_status.html: 删除卡密校验 IIFE", ok))

    m = re.search(r"\n[ \t]*/\* 体验版仅限控车页[^\n]*\n[ \t]*var _expPhone = '';", js)
    if m:
        mid = js.find(": fetch('https://incallapi.changan.com.cn", m.start())
        if mid > 0:
            js = js[:m.start()] + "\n    /* 直接刷新 token */\n    var _chain = " + js[mid + 2:]
            log.append(("vehicle_status.js: 卡密校验链改为直连 token", True))
    else:
        log.append(("vehicle_status.js: 卡密校验链改为直连 token", False))
    return html, js, log


# ---------------------------------------------------------------- 入口


def apply(html_index, html_user, html_vs, js_vs):
    i2, l1 = strip_index(html_index)
    u2, l2 = strip_user_info(html_user)
    v2, j2, l3 = strip_vehicle_status(html_vs, js_vs)
    return i2, u2, v2, j2, l1 + l2 + l3
