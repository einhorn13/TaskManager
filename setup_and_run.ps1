<#
.SYNOPSIS
  Разворачивает окружение для Flutter (Windows) и запускает task_manager.

.USAGE
  Запусти PowerShell от имени администратора (нужно для Chocolatey/winget при первой установке),
  положи этот скрипт прямо в папку task_manager (рядом с pubspec.yaml) и выполни:

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\setup_and_run.ps1

  Если Flutter/Git/Visual Studio уже стоят — скрипт просто пропустит эти шаги и перейдёт к запуску.
#>

$ErrorActionPreference = "Stop"
$ProjectDir = $PSScriptRoot
$FlutterDir = "C:\src\flutter"

function Test-Command($name) {
  return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

Write-Host "== 1. Проверка winget ==" -ForegroundColor Cyan
if (-not (Test-Command "winget")) {
  Write-Host "winget не найден. Обнови Windows 11 / установи 'App Installer' из Microsoft Store и перезапусти скрипт." -ForegroundColor Red
  exit 1
}

Write-Host "== 2. Git ==" -ForegroundColor Cyan
if (-not (Test-Command "git")) {
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
  Write-Host "Git установлен. Перезапусти PowerShell, чтобы обновился PATH, затем запусти скрипт заново." -ForegroundColor Yellow
  exit 0
} else {
  Write-Host "Git уже установлен: $(git --version)"
}

Write-Host "== 3. Visual Studio Build Tools (нужны для сборки под Windows) ==" -ForegroundColor Cyan
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasCppWorkload = $false
if (Test-Path $vswhere) {
  $found = & $vswhere -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
  if ($found) { $hasCppWorkload = $true }
}
if (-not $hasCppWorkload) {
  Write-Host "Не найден компонент 'Desktop development with C++'." -ForegroundColor Yellow
  Write-Host "Это самая долгая часть установки (несколько ГБ). Запусти вручную и следуй мастеру:" -ForegroundColor Yellow
  Write-Host "  winget install --id Microsoft.VisualStudio.2022.Community -e" -ForegroundColor Yellow
  Write-Host "После установки Visual Studio открой 'Visual Studio Installer' -> Modify -> отметь 'Desktop development with C++' -> Modify." -ForegroundColor Yellow
  Write-Host "Затем запусти этот скрипт заново." -ForegroundColor Yellow
  exit 0
} else {
  Write-Host "Компонент C++ для Desktop уже установлен."
}

Write-Host "== 4. Flutter SDK ==" -ForegroundColor Cyan
if (-not (Test-Command "flutter")) {
  if (-not (Test-Path $FlutterDir)) {
    git clone https://github.com/flutter/flutter.git -b stable $FlutterDir
  }
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($userPath -notlike "*$FlutterDir\bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$FlutterDir\bin;$userPath", "User")
  }
  $env:Path = "$FlutterDir\bin;$env:Path"
  Write-Host "Flutter установлен в $FlutterDir и добавлен в PATH (User)." -ForegroundColor Yellow
  Write-Host "Перезапусти PowerShell, чтобы PATH подхватился во всех новых окнах, затем запусти скрипт снова." -ForegroundColor Yellow
  exit 0
} else {
  Write-Host "Flutter уже установлен: $(flutter --version | Select-Object -First 1)"
}

Write-Host "== 5. flutter doctor (диагностика окружения) ==" -ForegroundColor Cyan
flutter config --enable-windows-desktop
flutter doctor

Write-Host "== 6. Платформенные файлы (windows/, android/) ==" -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $ProjectDir "pubspec.yaml"))) {
  Write-Host "Не найден pubspec.yaml в $ProjectDir." -ForegroundColor Red
  Write-Host "Убедись, что скрипт лежит прямо внутри папки task_manager (рядом с pubspec.yaml)." -ForegroundColor Red
  exit 1
}
Set-Location $ProjectDir
if (-not (Test-Path (Join-Path $ProjectDir "windows"))) {
  Write-Host "Папка windows/ отсутствует — проект писался вручную, без 'flutter create'. Добавляю платформенные файлы."
  flutter create . --platforms=windows,android
}

Write-Host "== 7. Зависимости проекта ==" -ForegroundColor Cyan
flutter pub get

Write-Host "== 8. Генерация drift-кода (database.g.dart) ==" -ForegroundColor Cyan
dart run build_runner build --delete-conflicting-outputs

Write-Host "== 9. Запуск приложения на Windows ==" -ForegroundColor Cyan
flutter run -d windows
