# Builds the Windows release and packs it into a proper installer (Inno Setup):
# choose install folder, desktop / Start menu shortcuts, uninstaller, launch after install.
# Run: double-click tools\build_installer.bat or `powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1`
# -SkipBuild packs an already built build\windows\x64\runner\Release without a new `flutter build`.
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# 1. Find the Inno Setup compiler
$iscc = $null
$cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($cmd) { $iscc = $cmd.Source }
if (-not $iscc) {
    foreach ($base in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        foreach ($sub in 'Programs\Inno Setup 6', 'Inno Setup 6') {
            $p = Join-Path $base "$sub\ISCC.exe"
            if (Test-Path $p) { $iscc = $p; break }
        }
        if ($iscc) { break }
    }
}
if (-not $iscc) {
    throw "Inno Setup not found. Install it once: winget install JRSoftware.InnoSetup  (then run this script again)"
}

# 2. Build the release
if (-not $SkipBuild) {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
}
$rel = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $rel 'MikiMiki.exe'))) { throw "No $rel\MikiMiki.exe: run without -SkipBuild" }

$ver = ((Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]

# 3. Stage: release folder + Visual C++ runtime DLLs (app-local deployment is allowed by the license),
#    so the app starts on a clean PC without a separate Redistributable
$stage = Join-Path $root 'build\installer\stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item (Split-Path $stage -Parent) -ItemType Directory -Force | Out-Null
Copy-Item $rel $stage -Recurse
$crt = 'vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll','msvcp140_1.dll','msvcp140_2.dll','msvcp140_atomic_wait.dll','msvcp140_codecvt_ids.dll','concrt140.dll'
$dirs = @()
foreach ($base in @($env:VCToolsRedistDir, (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio'), (Join-Path $env:ProgramFiles 'Microsoft Visual Studio'))) {
    if ($base -and (Test-Path $base)) {
        $dirs += Get-ChildItem $base -Recurse -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'x64' } | Sort-Object FullName -Descending | ForEach-Object FullName
    }
}
$dirs += Join-Path $env:WINDIR 'System32'
foreach ($name in $crt) {
    if (Test-Path (Join-Path $stage $name)) { continue }
    foreach ($d in $dirs) {
        $f = Join-Path $d $name
        if (Test-Path $f) { Copy-Item $f $stage; break }
    }
}
foreach ($must in 'vcruntime140.dll','msvcp140.dll') {
    if (-not (Test-Path (Join-Path $stage $must))) { Write-Warning "$must not found: a clean PC will need the Visual C++ Redistributable" }
}

# 4. Compile the installer
& $iscc "/DAppVersion=$ver" "/DSourceDir=$stage" (Join-Path $PSScriptRoot 'installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compile failed' }
"Done: " + (Join-Path $root "build\MikiMiki-Setup-$ver.exe")
