# Збирає Windows-реліз і пакує його в один саморозпаковуючий exe (вбудований IExpress, нічого ставити не треба).
# Запуск: двічі клацнути tools\pack_windows.bat або `powershell -ExecutionPolicy Bypass -File tools\pack_windows.ps1`
# Ключ -SkipBuild пакує вже зібраний build\windows\x64\runner\Release без нового `flutter build`.
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if (-not $SkipBuild) {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows не вдався' }
}

$rel = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $rel 'MikiMiki.exe'))) { throw "Немає $rel\MikiMiki.exe: збудуй реліз (без -SkipBuild)" }

$ver = ((Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]
$work = Join-Path $root 'build\sfx'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item $work -ItemType Directory | Out-Null

# Складаємо те, що поїде в інсталятор: реліз (exe, flutter_windows.dll, libmpv та інші dll плагінів, data) + рантайм Visual C++,
# щоб програма запускалась і на чистому ПК без окремого встановлення Redistributable (app-local розгортання CRT дозволене ліцензією)
$stage = Join-Path $work 'stage'
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
    if (-not (Test-Path (Join-Path $stage $must))) { Write-Warning "Не знайшов ${must}: на чистому ПК знадобиться Visual C++ Redistributable" }
}
'У інсталятор потрапили dll: ' + ((Get-ChildItem $stage -Filter *.dll | ForEach-Object Name) -join ', ')

# IExpress не зберігає підтеки, тож кладемо все одним архівом і розпаковуємо install.cmd
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath (Join-Path $work 'app.zip') -CompressionLevel Fastest

$cmd = @'
@echo off
setlocal
set "DST=%LOCALAPPDATA%\Programs\MikiMiki"
taskkill /f /im MikiMiki.exe >nul 2>&1
if not exist "%DST%" mkdir "%DST%"
tar -xf app.zip -C "%DST%" 2>nul
if errorlevel 1 powershell -NoProfile -Command "Expand-Archive -LiteralPath 'app.zip' -DestinationPath $env:DST -Force"
powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell; foreach($d in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){ $l=$s.CreateShortcut((Join-Path $d 'Miki Miki.lnk')); $l.TargetPath=Join-Path $env:DST 'MikiMiki.exe'; $l.WorkingDirectory=$env:DST; $l.Save() }"
start "" "%DST%\MikiMiki.exe"
'@
Set-Content -Path (Join-Path $work 'install.cmd') -Value ($cmd -replace "`r?`n", "`r`n") -Encoding ASCII

$out = Join-Path $root "build\MikiMiki-Setup-$ver.exe"
if (Test-Path $out) { Remove-Item $out -Force }
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$out
FriendlyName=Miki Miki $ver
AppLaunched=cmd /c install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
FILE0="app.zip"
FILE1="install.cmd"
[SourceFiles]
SourceFiles0=$work\
[SourceFiles0]
%FILE0%=
%FILE1%=
"@
$sedPath = Join-Path $work 'pack.sed'
Set-Content -Path $sedPath -Value $sed -Encoding ASCII

& "$env:WINDIR\System32\iexpress.exe" /N /Q $sedPath | Out-Null
for ($i = 0; $i -lt 120 -and -not (Test-Path $out); $i++) { Start-Sleep -Milliseconds 500 }
if (-not (Test-Path $out)) { throw 'IExpress не створив exe' }
'{0}: {1:N1} МБ' -f $out, ((Get-Item $out).Length / 1MB)
