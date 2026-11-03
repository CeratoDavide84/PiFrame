<#
.SYNOPSIS
    Builds and packages the PiFrame Windows installer using Inno Setup,
    mirroring the exact pipeline executed by GitHub Actions release workflow.

.PARAMETER Version
    Semantic version string (e.g. 1.1.1). If omitted, extracted from package.json.

.PARAMETER SkipBuild
    Skip running pnpm and flutter build steps; only stage assets and recompile installer.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Version,

    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

# 1. Resolve Version
if ([string]::IsNullOrWhiteSpace($Version)) {
    $packageJsonPath = Join-Path $repoRoot 'package.json'
    if (Test-Path $packageJsonPath) {
        $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
        $Version = $packageJson.version
    }
}

if ([string]::IsNullOrWhiteSpace($Version) -or ($Version -notmatch '^\d+\.\d+\.\d+')) {
    Write-Error "Invalid or missing semantic version: '$Version'. Please supply a version like '1.1.1' or ensure package.json has a valid version."
    exit 1
}

Write-Host "=== Building PiFrame Windows Installer v$Version ===" -ForegroundColor Cyan

# 2. Locate Inno Setup Compiler (ISCC)
$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if (!(Test-Path $iscc)) {
    $isccCmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($isccCmd) {
        $iscc = $isccCmd.Source
    }
}
if (!$iscc -or !(Test-Path $iscc)) {
    Write-Error "Inno Setup 6 (ISCC.exe) was not found.`nPlease install Inno Setup 6 via: winget install JRSoftware.InnoSetup"
    exit 1
}
Write-Host "Using Inno Setup compiler: $iscc" -ForegroundColor Gray

# 3. Build components (unless -SkipBuild is specified)
if (-not $SkipBuild) {
    Write-Host "`n[1/4] Installing dependencies & building TypeScript packages..." -ForegroundColor Yellow
    pnpm install
    if ($LASTEXITCODE -ne 0) { throw "pnpm install failed" }

    pnpm --filter @piframe/pcp-ts run build
    if ($LASTEXITCODE -ne 0) { throw "Building @piframe/pcp-ts failed" }

    pnpm --filter @piframe/agentd run build:bundle
    if ($LASTEXITCODE -ne 0) { throw "Building @piframe/agentd bundle failed" }

    Write-Host "`n[2/4] Building Flutter desktop app (Windows Release)..." -ForegroundColor Yellow
    Push-Location 'apps/pi_frame'
    try {
        flutter build windows --release --build-name $Version --build-number 1 --dart-define="PI_FRAME_VERSION=$Version"
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

        Write-Host "`n[3/4] Building Flutter web app (remote access assets)..." -ForegroundColor Yellow
        flutter build web --release --no-web-resources-cdn --dart-define="PI_FRAME_VERSION=$Version"
        if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "`n[-SkipBuild specified: skipping pnpm and flutter build steps]" -ForegroundColor DarkYellow
}

# 4. Stage release bundle
Write-Host "`n[4/4] Staging runtime assets & compiling Inno Setup installer..." -ForegroundColor Yellow
$bundle = Join-Path $repoRoot 'apps/pi_frame/build/windows/x64/runner/Release'
if (!(Test-Path $bundle)) {
    throw "Release directory not found: $bundle. Did Flutter build succeed?"
}

# Terminate any stale processes running from the release bundle directory (e.g. background daemon node.exe or PiFrame.exe)
Get-Process -Name "node", "PiFrame" -ErrorAction SilentlyContinue | Where-Object {
    try {
        $_.Path -and ($_.Path.StartsWith($bundle, [System.StringComparison]::OrdinalIgnoreCase))
    }
    catch {
        $false
    }
} | ForEach-Object {
    Write-Host "Stopping stale process running from release bundle: $($_.ProcessName) (PID $($_.Id))..." -ForegroundColor DarkYellow
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}

# Clean up temporary WebView2 runtime user data generated during local app runs
$webView2Dir = Join-Path $bundle 'PiFrame.exe.WebView2'
if (Test-Path $webView2Dir) {
    Remove-Item $webView2Dir -Recurse -Force -ErrorAction SilentlyContinue
}

# Copy daemon bundle
Copy-Item (Join-Path $repoRoot 'apps/agentd/dist/pi-agentd.cjs') $bundle -Force

# Copy Node runtime executable
$nodePath = $null
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $nodePath = $nodeCmd.Source
}
if (!$nodePath -or !(Test-Path $nodePath)) {
    throw "Node.js executable ('node') not found on PATH."
}
$targetNode = Join-Path $bundle 'node.exe'
$copied = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        Copy-Item $nodePath $targetNode -Force
        $copied = $true
        break
    }
    catch {
        if ($attempt -lt 3) {
            Start-Sleep -Milliseconds 500
        }
    }
}
if (!$copied) {
    if ((Test-Path $targetNode) -and ((Get-Item $nodePath).Length -eq (Get-Item $targetNode).Length)) {
        Write-Warning "Could not overwrite '$targetNode' because it is locked by another process, but destination exists and size matches source. Proceeding with existing file."
    }
    else {
        throw "Failed to copy Node executable to '$targetNode'. Ensure no processes (such as PiFrame or node) are running from that directory."
    }
}

# Copy Node license
$nodeLicense = Join-Path (Split-Path $nodePath -Parent) 'LICENSE'
if (Test-Path $nodeLicense) {
    Copy-Item $nodeLicense (Join-Path $bundle 'NODE-LICENSE.txt') -Force
}
else {
    "Node.js Runtime License" | Out-File -FilePath (Join-Path $bundle 'NODE-LICENSE.txt') -Encoding utf8
}

# Copy Flutter web assets
Copy-Item (Join-Path $repoRoot 'apps/pi_frame/build/web') (Join-Path $bundle 'web') -Recurse -Force

# Verify bundle integrity
$requiredFiles = @('PiFrame.exe', 'pi-agentd.cjs', 'node.exe', 'NODE-LICENSE.txt', 'web/index.html')
foreach ($f in $requiredFiles) {
    $fullPath = Join-Path $bundle $f
    if (!(Test-Path $fullPath)) {
        throw "Bundle verification failed: missing required component '$f' at '$fullPath'."
    }
}

# 5. Compile Installer with Inno Setup
$distDir = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Force $distDir | Out-Null
$issPath = Join-Path $repoRoot 'packaging/windows/piframe.iss'

& $iscc "/DAppVersion=$Version" "/DSourceDir=$bundle" "/DOutputDir=$distDir" $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

$expectedInstaller = Join-Path $distDir "PiFrame-Setup-$Version-windows-x64.exe"
if (Test-Path $expectedInstaller) {
    $fileInfo = Get-Item $expectedInstaller
    $sizeMb = [math]::Round($fileInfo.Length / 1MB, 2)
    Write-Host "`n Installer generated successfully!" -ForegroundColor Green
    Write-Host "Location: $expectedInstaller ($sizeMb MB)" -ForegroundColor Cyan
}
else {
    Write-Host "`n Installer created in: $distDir" -ForegroundColor Green
}
