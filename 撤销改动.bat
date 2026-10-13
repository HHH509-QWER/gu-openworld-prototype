@echo off
cd /d "%~dp0"

echo ==========================================
echo   撤销所有未提交的改动
echo ==========================================
echo.
echo 这会把你改过但还没提交的内容全部丢掉，
echo 恢复到上一次提交时的样子。
echo.
echo --- 即将被丢弃的改动 ---
git status --short
echo.

set "OK="
set /p "OK=确定要撤销吗？输入 y 确认，其他键取消: "
if /i not "%OK%"=="y" (
  echo.
  echo 已取消，什么都没做。
  echo.
  pause
  exit /b 0
)

git checkout .
echo.
echo ==========================================
echo   [完成] 已恢复到上次提交的状态
echo ==========================================
echo.
pause
