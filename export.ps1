[CmdletBinding()]
param(
    [ValidateSet('all', 'windows', 'android')]
    [string]$Platform = 'all',
    [string]$OutputRoot,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found in PATH.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot 'dist'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

$pubspec = Get-Content (Join-Path $projectRoot 'pubspec.yaml') -Encoding UTF8
$versionLine = $pubspec | Where-Object { $_ -match '^version:\s*(\S+)' } | Select-Object -First 1
if (-not $versionLine -or $versionLine -notmatch '^version:\s*(\S+)') {
    throw 'Could not read version from pubspec.yaml.'
}
$version = $Matches[1]
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$releaseDir = Join-Path $OutputRoot "TaskManager_${version}_$timestamp"
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

$defines = @()
$envFile = Join-Path $projectRoot 'supabase.env'
if (Test-Path $envFile) {
    $config = @{}
    foreach ($line in Get-Content $envFile -Encoding UTF8) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) { $config[$parts[0].Trim()] = $parts[1].Trim() }
    }
    if ($config.SUPABASE_URL -and $config.SUPABASE_ANON_KEY) {
        $defines += "--dart-define=SUPABASE_URL=$($config.SUPABASE_URL)"
        $defines += "--dart-define=SUPABASE_ANON_KEY=$($config.SUPABASE_ANON_KEY)"
    }
} else {
    Write-Warning 'supabase.env is missing: this build will only support offline sign-in.'
}

if ($Clean) {
    & flutter clean
    if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed.' }
}

& flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
& flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }
& flutter test
if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }

$artifacts = @()

if ($Platform -in @('all', 'windows')) {
    & flutter build windows --release @defines
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }

    $windowsSource = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    if (-not (Test-Path $windowsSource)) { throw "Windows build was not found: $windowsSource" }
    $windowsZip = Join-Path $releaseDir "TaskManager_Windows_x64_$version.zip"
    Compress-Archive -Path (Join-Path $windowsSource '*') -DestinationPath $windowsZip -Force
    $artifacts += $windowsZip
}

if ($Platform -in @('all', 'android')) {
    if (-not (Test-Path (Join-Path $projectRoot 'android\key.properties'))) {
        throw 'Android release key is not configured. Follow the Android section in docs/INSTALL_AND_EXPORT.md.'
    }
    & flutter build apk --release @defines
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }

    $apkSource = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    $apkTarget = Join-Path $releaseDir "TaskManager_Android_$version.apk"
    Copy-Item -LiteralPath $apkSource -Destination $apkTarget
    $artifacts += $apkTarget
}

$checksumFile = Join-Path $releaseDir 'SHA256SUMS.txt'
$checksumLines = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash.ToLowerInvariant()
    "$hash  $([System.IO.Path]::GetFileName($artifact))"
}
$checksumLines | Set-Content -Path $checksumFile -Encoding ASCII

Write-Host "Done: $releaseDir"
$artifacts | ForEach-Object { Write-Host " - $_" }
