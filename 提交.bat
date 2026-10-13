@echo off
cd /d "%~dp0"

echo ==========================================
echo   提交并上传到 GitHub
echo ==========================================
echo.

echo --- 这次改动的文件 ---
git status --short
echo.

set "MSG="
set /p "MSG=提交说明（直接回车 = 用时间戳）: "
if "%MSG%"=="" set "MSG=更新 %DATE% %TIME%"

echo.
echo --- 正在提交 ---
git add .
git commit -m "%MSG%"
if errorlevel 1 (
  echo.
  echo [跳过] 没有需要提交的改动，或者提交失败。
  echo.
  pause
  exit /b 1
)

echo.
echo --- 正在上传到 GitHub ---
git push
if errorlevel 1 (
  echo.
  echo [失败] 上传失败。可能是网络问题，稍后再试一次。
  echo.
  pause
  exit /b 1
)

echo.
echo ==========================================
echo   [成功] 已上传
echo   https://github.com/HHH509-QWER/gu-openworld-prototype
echo ==========================================
echo.
pause
