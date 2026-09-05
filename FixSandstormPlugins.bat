@echo off
setlocal
title Sandstorm Mod Tools - Plugin Module Fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$Root='%~dp0'; $src=(Get-Content -LiteralPath '%~f0' -Raw) -split ':::PSCODE\r?\n',2; Invoke-Expression $src[1]"
echo.
pause
exit /b
:::PSCODE
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Sandstorm Mod Tools - Plugin Module Fix
#
#  https://github.com/WintorOperator/sandstormmodtools-plugin-fix
#
#  Rewrites the mismatched BuildId in each plugin's UE4Editor.modules manifest
#  to match the editor's own. See README.md for the full explanation.
#
#  The correct BuildId is always read from the editor's own manifest at
#  runtime. No GUID is hardcoded -- this must stay true, because the values
#  differ between mod tools builds.
# ---------------------------------------------------------------------------

$Root           = $Root.TrimEnd('\')
$Engine         = Join-Path $Root 'Engine'
$EditorManifest = Join-Path $Engine 'Binaries\Win64\UE4Editor.modules'
$PluginsDir     = Join-Path $Engine 'Plugins'
$BackupDir      = Join-Path $Root 'PluginManifestBackup'

function Write-Rule { Write-Host ('-' * 74) -ForegroundColor DarkGray }

function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Rule
    Write-Host "  $Text" -ForegroundColor White
    Write-Rule
}

function Confirm-Step {
    param([string]$Question)
    while ($true) {
        Write-Host ''
        Write-Host $Question -ForegroundColor White
        $answer = Read-Host '    Type Y or N'
        if ($answer -match '^\s*(y|yes)\s*$') { return $true }
        if ($answer -match '^\s*(n|no)\s*$')  { return $false }
        Write-Host '  Please answer Y or N.' -ForegroundColor Yellow
    }
}

function Stop-With {
    param([string]$Message)
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor Red
    Write-Host ''
    exit 1
}

# Reads the BuildId out of every plugin manifest.
function Get-ManifestState {
    param($Files)
    foreach ($file in $Files) {
        $id = '<unreadable>'
        try { $id = (Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json).BuildId } catch { }
        if ([string]::IsNullOrWhiteSpace($id)) { $id = '<unreadable>' }
        [pscustomobject]@{ Path = $file.FullName; BuildId = $id }
    }
}

function Show-State {
    param($State, [string]$EditorId, [string]$Caption)
    Write-Host ''
    Write-Host "  $Caption" -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('    {0,-38} {1,9}  {2}' -f 'BuildId', 'Manifests', 'Status')
    Write-Host ('    {0,-38} {1,9}  {2}' -f ('-' * 38), '---------', '--------------')
    foreach ($group in ($State | Group-Object BuildId | Sort-Object Count -Descending)) {
        if ($group.Name -eq $EditorId) {
            Write-Host ('    {0,-38} {1,9}  {2}' -f $group.Name, $group.Count, 'MATCHES EDITOR') -ForegroundColor Green
        } else {
            Write-Host ('    {0,-38} {1,9}  {2}' -f $group.Name, $group.Count, 'MISMATCHED') -ForegroundColor Yellow
        }
    }
}

# Byte-level swap so the file's size, encoding and line endings are untouched.
# Only the 36 bytes of the GUID change.
function Set-BuildId {
    param([string]$Path, [string]$OldId, [string]$NewId)
    $old = [Text.Encoding]::ASCII.GetBytes($OldId)
    $new = [Text.Encoding]::ASCII.GetBytes($NewId)
    if ($old.Length -ne $new.Length) { throw "BuildId length mismatch for $Path" }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hits  = 0
    for ($i = 0; $i -le $bytes.Length - $old.Length; $i++) {
        $match = $true
        for ($k = 0; $k -lt $old.Length; $k++) {
            if ($bytes[$i + $k] -ne $old[$k]) { $match = $false; break }
        }
        if ($match) {
            for ($k = 0; $k -lt $new.Length; $k++) { $bytes[$i + $k] = $new[$k] }
            $hits++
            $i += $old.Length - 1
        }
    }
    if ($hits -gt 0) { [IO.File]::WriteAllBytes($Path, $bytes) }
    return $hits
}

# ---------------------------------------------------------------------------
#  Introduction
# ---------------------------------------------------------------------------

Clear-Host
Write-Title 'SANDSTORM MOD TOOLS - PLUGIN MODULE FIX'
Write-Host ''
Write-Host '  Fixes the "Missing Modules" error by correcting the build ID stamped on'
Write-Host '  each plugin manifest. Only UE4Editor.modules text files under'
Write-Host '  Engine\Plugins are changed -- no DLLs, assets, config or .uproject.'
Write-Host ''
Write-Host '  Details: github.com/WintorOperator/sandstormmodtools-plugin-fix' -ForegroundColor Gray
Write-Host ''
Write-Host "  Editor location : $Root"

# ---------------------------------------------------------------------------
#  Environment checks
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $EditorManifest)) {
    Stop-With ("Could not find Engine\Binaries\Win64\UE4Editor.modules here.`r`n" +
               "  Place this .bat in the ROOT of your Sandstorm Editor folder --`r`n" +
               "  the folder that contains 'Engine' and 'Insurgency' -- and run it again.")
}
if (-not (Test-Path -LiteralPath $PluginsDir)) {
    Stop-With 'Could not find Engine\Plugins. This does not look like a Sandstorm Editor install.'
}

$running = @(Get-Process -Name 'UE4Editor', 'UE4Editor-Cmd' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Stop-With 'The Unreal Editor is currently running. Close it completely, then run this again.'
}

$editorId = (Get-Content -LiteralPath $EditorManifest -Raw | ConvertFrom-Json).BuildId
if ([string]::IsNullOrWhiteSpace($editorId)) {
    Stop-With 'The editor manifest has no BuildId. Nothing safe to do.'
}

$manifests = @(Get-ChildItem -LiteralPath $PluginsDir -Recurse -Filter 'UE4Editor.modules' -File)
if ($manifests.Count -eq 0) {
    Stop-With 'No plugin manifests found under Engine\Plugins.'
}

Write-Host "  Editor BuildId  : $editorId" -ForegroundColor Green

$before     = @(Get-ManifestState $manifests)
$mismatched = @($before | Where-Object { $_.BuildId -ne $editorId -and $_.BuildId -ne '<unreadable>' })
$unreadable = @($before | Where-Object { $_.BuildId -eq '<unreadable>' })

Write-Title 'CURRENT STATE'
Show-State -State $before -EditorId $editorId -Caption ('BEFORE  ({0} plugin manifests scanned)' -f $before.Count)

if ($unreadable.Count -gt 0) {
    Write-Host ''
    Write-Host ("  {0} manifest(s) could not be parsed and will be left alone." -f $unreadable.Count) -ForegroundColor Yellow
}

if ($mismatched.Count -eq 0) {
    Write-Host ''
    Write-Host '  Every plugin manifest already matches the editor. Nothing to fix.' -ForegroundColor Green
    Write-Host ''
    exit 0
}

Write-Host ''
Write-Host ("  {0} of {1} plugin manifests carry the wrong build ID." -f $mismatched.Count, $before.Count) -ForegroundColor Yellow

# ---------------------------------------------------------------------------
#  Step 1 - Backup
# ---------------------------------------------------------------------------

Write-Title 'STEP 1 OF 2 - BACK UP THE ORIGINAL MANIFESTS'
Write-Host ''
Write-Host "  All $($before.Count) UE4Editor.modules files will be copied to:"
Write-Host "    $BackupDir" -ForegroundColor White
Write-Host ''
Write-Host '  This is roughly 70 KB and gives you a complete undo. The companion'
Write-Host '  script RestoreSandstormPlugins.bat restores from this folder.'

$existingBackup = @()
if (Test-Path -LiteralPath $BackupDir) {
    $existingBackup = @(Get-ChildItem -LiteralPath $BackupDir -Recurse -Filter 'UE4Editor.modules' -File -ErrorAction SilentlyContinue)
}

$doBackup = $false
if ($existingBackup.Count -gt 0) {
    Write-Host ''
    Write-Host ("  A backup already exists here ({0} files, created {1})." -f $existingBackup.Count, (Get-Item -LiteralPath $BackupDir).CreationTime) -ForegroundColor Yellow
    Write-Host '  Keeping it is almost always right -- overwriting it now would replace' -ForegroundColor Yellow
    Write-Host '  your original manifests with whatever is on disk today.' -ForegroundColor Yellow
    if (Confirm-Step '  Overwrite the existing backup?') { $doBackup = $true }
    else { Write-Host '  Keeping the existing backup.' -ForegroundColor Green }
} else {
    $doBackup = Confirm-Step '  Back up the plugin manifests now?'
}

if ($doBackup) {
    Write-Host ''
    Write-Host '  Backing up...' -NoNewline
    $copied = 0
    foreach ($manifest in $manifests) {
        $relative = $manifest.FullName.Substring($Engine.Length).TrimStart('\')
        $target   = Join-Path $BackupDir $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $manifest.FullName -Destination $target -Force
        $copied++
    }
    Write-Host " done. $copied manifests copied." -ForegroundColor Green
} elseif ($existingBackup.Count -eq 0) {
    Write-Host ''
    Write-Host '  No backup will be made. You will have no automatic way to undo this.' -ForegroundColor Red
    if (-not (Confirm-Step '  Continue anyway without a backup?')) {
        Write-Host ''
        Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor Yellow
        Write-Host ''
        exit 0
    }
}

# ---------------------------------------------------------------------------
#  Step 2 - Fix
# ---------------------------------------------------------------------------

Write-Title 'STEP 2 OF 2 - CORRECT THE BUILD ID'
Write-Host ''
Write-Host ("  {0} manifests will have their BuildId rewritten to:" -f $mismatched.Count)
Write-Host "    $editorId" -ForegroundColor White
Write-Host ''
Write-Host '  36 bytes change per file. File size, encoding and line endings stay'
Write-Host '  identical. Manifests that already match are skipped.'

if (-not (Confirm-Step '  Apply the fix now?')) {
    Write-Host ''
    Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

Write-Host ''
Write-Host '  Applying...' -NoNewline
$fixed   = 0
$skipped = @()
foreach ($entry in $mismatched) {
    if ($entry.BuildId.Length -ne $editorId.Length) {
        $skipped += $entry
        continue
    }
    try {
        if ((Set-BuildId -Path $entry.Path -OldId $entry.BuildId -NewId $editorId) -gt 0) { $fixed++ }
    } catch {
        $skipped += $entry
    }
}
Write-Host " done. $fixed manifests rewritten." -ForegroundColor Green

if ($skipped.Count -gt 0) {
    Write-Host ''
    Write-Host ("  {0} manifest(s) were skipped (unexpected format or read-only):" -f $skipped.Count) -ForegroundColor Yellow
    foreach ($entry in ($skipped | Select-Object -First 10)) {
        Write-Host ("    {0}" -f $entry.Path.Substring($Engine.Length).TrimStart('\')) -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
#  Verification
# ---------------------------------------------------------------------------

Write-Title 'VERIFICATION'

$after = @(Get-ManifestState $manifests)

Show-State -State $before -EditorId $editorId -Caption 'BEFORE'
Show-State -State $after  -EditorId $editorId -Caption 'AFTER'

$sample = @($mismatched | Select-Object -First 3)
if ($sample.Count -gt 0) {
    Write-Host ''
    Write-Host '  Sample of changed files:' -ForegroundColor Cyan
    foreach ($entry in $sample) {
        $now = ($after | Where-Object { $_.Path -eq $entry.Path }).BuildId
        Write-Host ''
        Write-Host ('    ' + $entry.Path.Substring($Engine.Length).TrimStart('\'))
        Write-Host ("      before : {0}" -f $entry.BuildId) -ForegroundColor Yellow
        Write-Host ("      after  : {0}" -f $now) -ForegroundColor Green
    }
}

$stillWrong = @($after | Where-Object { $_.BuildId -ne $editorId })

Write-Host ''
Write-Rule
if ($stillWrong.Count -eq 0) {
    Write-Host '  RESULT: PASS - every plugin manifest now matches the editor.' -ForegroundColor Green
    Write-Rule
    Write-Host ''
    Write-Host '  Next steps:'
    Write-Host '    1. Launch the Sandstorm editor and open your project.'
    Write-Host '    2. Go to Edit > Plugins and enable the plugins you need.'
    Write-Host '    3. Restart the editor when prompted.'
    Write-Host ''
    Write-Host '  Note: a mod tools update from NWI may restore the old manifests.'
    Write-Host '  If the error comes back, just run this tool again.'
} else {
    Write-Host ("  RESULT: {0} manifest(s) still do not match." -f $stillWrong.Count) -ForegroundColor Yellow
    Write-Rule
    Write-Host ''
    Write-Host '  Run RestoreSandstormPlugins.bat to put the originals back, then open'
    Write-Host '  an issue on GitHub with the output above.'
}
Write-Host ''
