@echo off
chcp 65001 >nul
setlocal

set "F=C:\flutter\packages\flutter_tools\lib\src\android\gradle.dart"

if not exist "%F%" (
  echo ERROR: no file %F%
  pause
  exit /b 1
)

copy /y "%F%" "%F%.bak" >nul

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%F%'; $c=Get-Content -Raw -Encoding UTF8 $p;" ^
  "$c2=$c.Replace('throwToolExit(failedToStripDebugSymbolsErrorMessage);','/* strip-check disabled */ ;');" ^
  "if($c2 -eq $c){ $c2=$c.Replace(\"throwToolExit(failedToStripDebugSymbolsErrorMessage)\",\"/* strip-check disabled */\"); }" ^
  "if($c2 -eq $c){ Write-Host 'FAIL: pattern not found'; exit 1 };" ^
  "Set-Content -Path $p -Value $c2 -Encoding UTF8 -NoNewline; Write-Host 'OK patched'"

if errorlevel 1 (
  echo Trying alternate patch...
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$p='%F%'; $c=Get-Content -Raw -Encoding UTF8 $p;" ^
    "$c2=[regex]::Replace($c,'if\s*\(\(buildInfo\.mode\s*==\s*BuildMode\.release\)\s*&&\s*!\s*\(await\s*_isAabStrippedOfDebugSymbols[\s\S]*?\)\)\s*\{\s*throwToolExit\(failedToStripDebugSymbolsErrorMessage\);\s*\}','/* strip-check disabled */');" ^
    "if($c2 -eq $c){ Write-Host 'FAIL2'; exit 1 };" ^
    "Set-Content -Path $p -Value $c2 -Encoding UTF8 -NoNewline; Write-Host 'OK patched2'"
)

if errorlevel 1 (
  echo Patch failed
  pause
  exit /b 1
)

del /f C:\flutter\bin\cache\flutter_tools.stamp 2>nul
del /f C:\flutter\bin\cache\flutter_tools.snapshot 2>nul
del /f C:\flutter\bin\cache\flutter_tools.stamp 2>nul

echo.
echo Done. Run:
echo   cd /d C:\Users\dimal\sline
echo   flutter build appbundle --release
echo.
pause