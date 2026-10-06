@echo off
set CACHE=%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev
echo Patching plugins in %CACHE% ...
for /d %%D in ("%CACHE%\*") do (
  if exist "%%D\android\build.gradle" (
    powershell -NoProfile -Command ^
      "$p='%%D\android\build.gradle'; $c=Get-Content -Raw $p; $n=$c -replace 'compileSdkVersion\s+\d+','compileSdkVersion 36' -replace 'compileSdk\s*=\s*\d+','compileSdk = 36' -replace 'compileSdkVersion\s*=\s*\d+','compileSdkVersion = 36'; if($n -ne $c){ Set-Content -Path $p -Value $n -NoNewline; Write-Host Patched $p }"
  )
  if exist "%%D\android\build.gradle.kts" (
    powershell -NoProfile -Command ^
      "$p='%%D\android\build.gradle.kts'; $c=Get-Content -Raw $p; $n=$c -replace 'compileSdk\s*=\s*\d+','compileSdk = 36' -replace 'compileSdkVersion\s*=\s*\d+','compileSdkVersion = 36'; if($n -ne $c){ Set-Content -Path $p -Value $n -NoNewline; Write-Host Patched $p }"
  )
)
echo Done.