@echo off
chcp 65001 >nul
cd /d C:\Users\dimal\sline

echo [1] pub get...
call flutter pub get
if errorlevel 1 (
  echo ERROR: flutter pub get failed
  pause
  exit /b 1
)

echo.
echo [2] flutter_launcher_icons...
call dart run flutter_launcher_icons
if errorlevel 1 (
  echo.
  echo dart run failed, trying flutter pub run...
  call flutter pub run flutter_launcher_icons
)

echo.
echo Done. Code: %ERRORLEVEL%
pause