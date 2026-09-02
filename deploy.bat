@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================
echo   Wardia - Build and Deploy (one click)
echo ============================================
echo.

echo [1/4] Building Flutter web app...
call flutter build web --pwa-strategy=none
if errorlevel 1 (
  echo.
  echo *** FLUTTER BUILD FAILED - stopped here, nothing was sent. ***
  echo Copy the red error text above and send it to Claude.
  pause
  exit /b 1
)

echo.
echo [2/4] Copying build files into backend\public ...
xcopy /E /I /Y build\web backend\public >nul
if errorlevel 1 (
  echo.
  echo *** COPY FAILED. ***
  pause
  exit /b 1
)

echo.
echo [3/4] Saving changes to git...
git add -A
git commit -m "deploy: update %date% %time%"

echo.
echo [4/4] Uploading to GitHub (Railway will redeploy automatically)...
git push origin main
if errorlevel 1 (
  echo.
  echo *** PUSH FAILED. Check your internet connection or GitHub login. ***
  pause
  exit /b 1
)

echo.
echo ============================================
echo   DONE. Wait about 1 minute, then open:
echo   https://wardia-api-production.up.railway.app/
echo ============================================
pause
