#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""去掉原站的营销/联系方式/公告

清理内容：
 - 登录页：开发者 QQ、辱骂式售后声明、系统公告卡片
 - 我的页：关于（网页开发者 / 开发者 QQ）、更新公告入口
 - 更新公告弹窗 + 更新日志数组 + 置顶公告（招募代理，含站主 QQ）
 - copyOwnerQQ 等 QQ 相关函数与文案

保留：免责声明（法律文本）、使用说明链接、统计/白名单/代理等功能。
由 build.py 在 strip_card 之后调用。
"""
import re

from strip_card import cut_between, find_matching_brace, remove_element, remove_function, _skip_string  # noqa

QQ = "2317665079"


def strip_index(html):
    log = []

    before = html
    html = "\n".join(l for l in html.split("\n")
                     if "开发者QQ" not in l and "谁卖的售后找谁" not in l)
    log.append(("index: 删除开发者QQ与售后声明", html != before))

    html, ok = cut_between(html,
                           '            <div class="notice mt-6 p-4">',
                           '            <div class="mt-5 text-center">')
    log.append(("index: 删除系统公告卡片", ok))

    html, n = remove_function(html, "copyOwnerQQ")
    log.append(("index: 删除 copyOwnerQQ()", bool(n)))

    html = re.sub(r"\n[ \t]*\.notice\s*\{[^}]*\}", "", html)
    return html, log


def strip_user(html):
    log = []

    # 我的页：更新公告入口
    html, ok = cut_between(html,
                           '                    <div class="me-row" onclick="showUpdateNotice()">',
                           '                    <div class="me-row" onclick="openIconSheet()">')
    log.append(("user: 删除「更新公告」入口", ok))

    # 我的页：关于（开发者 + QQ）
    html, ok = cut_between(html,
                           '            <!-- 关于 -->',
                           "            <a href=\"/\" onclick=\"localStorage.removeItem('phone');")
    log.append(("user: 删除「关于 / 开发者QQ」区块", ok))

    # 更新公告弹窗
    html, ok = remove_element(html, "updateModal")
    log.append(("user: 删除更新公告弹窗", ok))

    # 更新日志 + 置顶公告（招募代理）+ 相关函数 + 自动弹出
    html, ok = cut_between(html,
                           "        /* ===== 更新公告（最近 10 条",
                           "        /* ===== 自定义桌面图标")
    log.append(("user: 删除更新日志/置顶公告/自动弹出逻辑", ok))

    # 兜底：任何残留 QQ 号与招募文案
    html = re.sub(r"\n[^\n]*" + QQ + r"[^\n]*", "", html)
    html = re.sub(r"\n[^\n]*招募[^\n]*", "", html)
    html = re.sub(r"\n[^\n]*站主 QQ[^\n]*", "", html)
    html = re.sub(r"\n[^\n]*开发者QQ[^\n]*", "", html)
    return html, log


def apply(html_index, html_user):
    i2, l1 = strip_index(html_index)
    u2, l2 = strip_user(html_user)
    return i2, u2, l1 + l2
