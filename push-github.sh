#!/usr/bin/env bash
# 用法：
#   GH_USER=你的用户名 GH_TOKEN=你的token REPO=car-ios ./push-github.sh
# token 在 GitHub → Settings → Developer settings → Personal access tokens 生成
# 勾选 repo 权限即可

set -e
: "${GH_USER:?请设置 GH_USER（GitHub 用户名）}"
: "${GH_TOKEN:?请设置 GH_TOKEN（Personal Access Token）}"
REPO="${REPO:-car-ios}"

echo "→ 检查/创建仓库 $GH_USER/$REPO"
if ! curl -sf -H "Authorization: token $GH_TOKEN" \
     "https://api.github.com/repos/$GH_USER/$REPO" >/dev/null; then
  curl -sf -X POST -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"$REPO\",\"private\":true,\"auto_init\":false}" \
    "https://api.github.com/user/repos" >/dev/null
  echo "  已创建私有仓库"
else
  echo "  仓库已存在"
fi

echo "→ 配置 remote 并推送"
git remote remove origin 2>/dev/null || true
git remote add origin "https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/$REPO.git"
git branch -M main
git push -u origin main

echo ""
echo "✓ 推送完成"
echo "  Actions: https://github.com/$GH_USER/$REPO/actions"
echo "  （workflow 只在 ios/ 有改动时自动触发，也可在页面上点 Run workflow）"
