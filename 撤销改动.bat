@echo off
cd /d "%~dp0"

echo ==========================================
echo   DISCARD uncommitted changes
echo ==========================================
echo.
echo This throws away everything you changed but
echo did not commit, restoring the last commit.
echo.
echo --- Files that WILL be restored ---
git status --short
echo.

set "OK="
set /p "OK=Type y to confirm, anything else cancels: "
if /i not "%OK%"=="y" (
  echo.
  echo Cancelled. Nothing was changed.
  echo.
  pause
  exit /b 0
)

git checkout .
echo.
echo [OK] Modified files restored to the last commit.
echo.
echo NOTE: brand-new files (shown as ?? above) are NOT
echo deleted on purpose, so you do not lose work you
echo meant to keep. Delete them by hand if unwanted.
echo.
pause