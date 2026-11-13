@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "site\index.html" python build.py
echo ============================================
echo   远程控车系统 - 本地复刻版（已去除卡密）
echo   演示账号 13800138000 / 控车码 123456
echo   管理密码 admin888
echo   登录即全功能解锁，无需卡密
echo ============================================
start "" http://127.0.0.1:8080
python server.py 8080
pause
