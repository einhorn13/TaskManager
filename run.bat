@echo off
setlocal

cd /d "%~dp0"

where flutter >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Flutter was not found in PATH.
  echo Install Flutter or add its bin directory to PATH, then try again.
  pause
  exit /b 1
)

if not exist "pubspec.yaml" (
  echo [ERROR] pubspec.yaml was not found in "%CD%".
  pause
  exit /b 1
)

if not exist "supabase.env" (
  echo [ERROR] supabase.env was not found.
  echo Copy supabase.env.example to supabase.env and fill in your project URL and publishable key.
  echo The app can still work offline, but run.bat intentionally starts in Supabase mode.
  pause
  exit /b 1
)

for /f "usebackq eol=# tokens=1,* delims==" %%A in ("supabase.env") do (
  set "%%A=%%B"
)

if not defined SUPABASE_URL (
  echo [ERROR] SUPABASE_URL is missing in supabase.env.
  pause
  exit /b 1
)
if not defined SUPABASE_ANON_KEY (
  echo [ERROR] SUPABASE_ANON_KEY is missing in supabase.env.
  pause
  exit /b 1
)

reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2>nul | find "0x1" >nul
if errorlevel 1 (
  fltmc >nul 2>&1
  if errorlevel 1 (
    echo [ERROR] Flutter cannot create plugin symlinks.
    echo Either:
    echo   1. Open Settings ^> System ^> For developers and enable Developer Mode.
    echo   2. Run this script from an elevated Administrator terminal.
    pause
    exit /b 1
  ) else (
    echo [WARNING] Developer Mode is disabled, but the script is elevated.
    echo Continuing with Administrator symlink privileges...
  )
)

echo Checking dependencies...
call flutter pub get
if errorlevel 1 goto :failed

rem Closing the window now hides the app in the tray. A previous development
rem instance would keep build\windows files locked and make CMake install fail.
tasklist /FI "IMAGENAME eq task_manager.exe" 2>nul | find /I "task_manager.exe" >nul
if not errorlevel 1 (
  echo [ERROR] Task Manager is already running and keeps the Debug build locked.
  echo Choose Exit from the Task Manager tray menu, then run this script again.
  echo Do not only close the window: closing now hides the app in the tray.
  pause
  exit /b 1
)

echo Starting Task Manager for Windows...
call flutter run -d windows ^
  --dart-define=SUPABASE_URL=%SUPABASE_URL% ^
  --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
if errorlevel 1 goto :failed

exit /b 0

:failed
echo.
echo [ERROR] Task Manager could not be started.
pause
exit /b 1
