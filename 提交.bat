@echo off
cd /d "%~dp0"

echo ==========================================
echo   Commit and push to GitHub
echo ==========================================
echo.
echo --- Changed files ---
git status --short
echo.

set "MSG="
set /p "MSG=Message (blank = timestamp): "
if "%MSG%"=="" set "MSG=update %DATE% %TIME%"

echo.
echo --- Committing ---
git add .
git commit -m "%MSG%"
if errorlevel 1 (
  echo.
  echo [SKIP] Nothing to commit, or commit failed.
  echo.
  pause
  exit /b 1
)

echo.
echo --- Pushing to GitHub ---
git push
if errorlevel 1 (
  echo.
  echo [FAIL] Push failed. Check network and try again.
  echo.
  pause
  exit /b 1
)

echo.
echo ==========================================
echo   [OK] Pushed
echo   https://github.com/HHH509-QWER/gu-openworld-prototype
echo ==========================================
echo.
pause