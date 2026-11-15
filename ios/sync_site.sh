#!/usr/bin/env bash
# 把构建好的 site/ 同步进 App 资源目录（供 WKURLSchemeHandler 读取）
# CI 上没有 site/ 时，直接沿用仓库里已提交的 ios/Resources/site
set -e
cd "$(dirname "$0")/.."

if [ ! -d "site" ]; then
  if [ -d "ios/Resources/site" ]; then
    echo "未找到 site/，沿用仓库内已有的 ios/Resources/site"
    echo "文件数：$(find ios/Resources/site -type f | wc -l | tr -d ' ')"
    exit 0
  fi
  echo "既没有 site/ 也没有 ios/Resources/site" >&2
  exit 1
fi

python - <<'PY'
import os, shutil
SRC, DST = "site", "ios/Resources/site"
if os.path.isdir(DST):
    shutil.rmtree(DST)
n = 0
for root, dirs, files in os.walk(SRC):
    rel = os.path.relpath(root, SRC)
    if "car3d" in rel.split(os.sep):
        continue
    out = os.path.join(DST, rel) if rel != "." else DST
    os.makedirs(out, exist_ok=True)
    for f in files:
        shutil.copy2(os.path.join(root, f), os.path.join(out, f))
        n += 1
size = sum(os.path.getsize(os.path.join(r, f))
           for r, _, fs in os.walk(DST) for f in fs) / 1048576
print(f"已同步 {n} 个文件，{size:.1f} MB")
PY
