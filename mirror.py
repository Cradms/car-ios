#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓取目标站点静态资源与页面，保存到 _dump/ 下（保留 URL 路径结构）。"""
import os, re, sys, json
import urllib.request, urllib.error, urllib.parse

BASE = "https://a9db267525c1cf6b2.app.workbuddy.host"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_dump")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

seen = set()
report = []


def local_path(url_path):
    p = urllib.parse.urlparse(url_path).path or "/"
    if p.endswith("/"):
        p += "index.html"
    if not os.path.splitext(p)[1]:
        p += ".html"
    return os.path.join(ROOT, p.lstrip("/").replace("/", os.sep))


def fetch(url, referer=None):
    if url in seen:
        return None
    seen.add(url)
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
        **({"Referer": referer} if referer else {}),
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read()
            ctype = r.headers.get("Content-Type", "")
            status = r.status
    except urllib.error.HTTPError as e:
        report.append({"url": url, "status": e.code, "type": "http-error"})
        print(f"  [{e.code}] {url}")
        return None
    except Exception as e:
        report.append({"url": url, "status": str(e), "type": "error"})
        print(f"  [ERR] {url} -> {e}")
        return None

    dst = local_path(url)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(body)
    report.append({"url": url, "status": status, "bytes": len(body), "type": ctype, "file": dst})
    print(f"  [{status}] {len(body):>8}  {ctype:<32} {url}")
    return body


ASSET_RE = re.compile(r'''(?:src|href)\s*=\s*["']([^"']+)["']''', re.I)
CSSURL_RE = re.compile(r"""url\(\s*["']?([^"')]+)["']?\s*\)""", re.I)
JSSTR_RE = re.compile(r'''["'`](/(?:static|api|user_info|login|assets|img|css|js)[^"'`\s]*)["'`]''')
ROUTE_RE = re.compile(r'''["'`](/(?:user_info|admin|login|home|dashboard|card|pay|order)[^"'`\s]*)["'`]''')


def norm(u, base_url):
    if u.startswith(("data:", "javascript:", "mailto:", "#", "tel:")):
        return None
    return urllib.parse.urljoin(base_url, u)


def main():
    print(f"== root: {BASE}")
    os.makedirs(ROOT, exist_ok=True)

    pages = ["/", "/user_info"]
    queue = [BASE + p for p in pages]
    done_pages = []
    while queue:
        url = queue.pop(0)
        body = fetch(url)
        if body is None:
            continue
        done_pages.append(url)
        try:
            text = body.decode("utf-8", "replace")
        except Exception:
            continue
        if "html" not in report[-1].get("type", ""):
            continue
        assets = set()
        for m in ASSET_RE.findall(text):
            n = norm(m, url)
            if n: assets.add(n)
        for m in CSSURL_RE.findall(text):
            n = norm(m, url)
            if n: assets.add(n)
        for m in JSSTR_RE.findall(text) + ROUTE_RE.findall(text):
            n = norm(m, url)
            if n: assets.add(n)
        for a in sorted(assets):
            if not a.startswith(BASE):
                continue
            clean = a.split("#")[0]
            if clean not in seen:
                queue.append(clean)

    with open(os.path.join(ROOT, "_report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(f"\n== done: {len(report)} resources, {len(done_pages)} pages")


if __name__ == "__main__":
    main()
