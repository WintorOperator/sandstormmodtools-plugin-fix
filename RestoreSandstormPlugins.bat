@echo off
setlocal
title Sandstorm Mod Tools - Restore Plugin Manifests
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$Root='%~dp0'; $src=(Get-Content -LiteralPath '%~f0' -Raw) -split ':::PSCODE\r?\n',2; Invoke-Expression $src[1]"
echo.
pause
exit /b
:::PSCODE
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Sandstorm Mod Tools - Restore Plugin Manifests
#  https://github.com/WintorOperator/sandstormmodtools-plugin-fix
#
#  Undoes FixSandstormPlugins.bat by copying the original UE4Editor.modules
#  files back out of PluginManifestBackup.
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

# ---------------------------------------------------------------------------
#  Introduction
# ---------------------------------------------------------------------------

Clear-Host
Write-Title 'SANDSTORM MOD TOOLS - RESTORE PLUGIN MANIFESTS'
Write-Host ''
Write-Host '  Undoes the fix by copying the original UE4Editor.modules files back from'
Write-Host '  your backup folder. The "Missing Modules" error will return -- that is'
Write-Host '  expected, the install goes back exactly as NWI shipped it.'
Write-Host ''
Write-Host '  Details: github.com/WintorOperator/sandstormmodtools-plugin-fix' -ForegroundColor Gray
Write-Host ''
Write-Host "  Editor location : $Root"
Write-Host "  Backup folder   : $BackupDir"

# ---------------------------------------------------------------------------
#  Environment checks
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $EditorManifest)) {
    Stop-With ("Could not find Engine\Binaries\Win64\UE4Editor.modules here.`r`n" +
               "  Place this .bat in the ROOT of your Sandstorm Editor folder --`r`n" +
               "  the folder that contains 'Engine' and 'Insurgency' -- and run it again.")
}
if (-not (Test-Path -LiteralPath $BackupDir)) {
    Stop-With ("No backup folder found at:`r`n  $BackupDir`r`n" +
               "  There is nothing to restore. A backup is only created when you`r`n" +
               "  answer Y to the backup step in FixSandstormPlugins.bat.")
}

$running = @(Get-Process -Name 'UE4Editor', 'UE4Editor-Cmd' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Stop-With 'The Unreal Editor is currently running. Close it completely, then run this again.'
}

$editorId = (Get-Content -LiteralPath $EditorManifest -Raw | ConvertFrom-Json).BuildId
$backups  = @(Get-ChildItem -LiteralPath $BackupDir -Recurse -Filter 'UE4Editor.modules' -File)
if ($backups.Count -eq 0) {
    Stop-With "The backup folder exists but contains no UE4Editor.modules files."
}

# Only restore over files that are actually still there.
$restorable = @()
$orphaned   = @()
foreach ($backup in $backups) {
    $relative = $backup.FullName.Substring($BackupDir.Length).TrimStart('\')
    $target   = Join-Path $Engine $relative
    if (Test-Path -LiteralPath $target) {
        $restorable += [pscustomobject]@{ Source = $backup.FullName; Target = $target; Relative = $relative }
    } else {
        $orphaned += $relative
    }
}

if ($restorable.Count -eq 0) {
    Stop-With 'None of the backed-up manifests match a file in this install.'
}

$manifests = @($restorable | ForEach-Object { Get-Item -LiteralPath $_.Target })
$before    = @(Get-ManifestState $manifests)

Write-Host "  Editor BuildId  : $editorId" -ForegroundColor Green
Write-Host "  Backed up files : $($backups.Count)"

Write-Title 'CURRENT STATE'
Show-State -State $before -EditorId $editorId -Caption ('BEFORE  ({0} manifests covered by the backup)' -f $before.Count)

if ($orphaned.Count -gt 0) {
    Write-Host ''
    Write-Host ("  {0} backed-up file(s) no longer exist in the install and will be skipped." -f $orphaned.Count) -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
#  Restore
# ---------------------------------------------------------------------------

Write-Title 'RESTORE'
Write-Host ''
Write-Host ("  {0} UE4Editor.modules files will be overwritten with the originals" -f $restorable.Count)
Write-Host '  from your backup folder. Nothing else is touched.'

$backupFiles = @($restorable | ForEach-Object { Get-Item -LiteralPath $_.Source })
$backupState = @(Get-ManifestState $backupFiles)

Show-State -State $backupState -EditorId $editorId -Caption 'THE BACKUP WILL RESTORE THESE BUILD IDs'

Write-Host ''
Write-Host "  Editor BuildId : $editorId" -ForegroundColor Green
Write-Host ''
Write-Host '  Compare the two above. Rows marked MISMATCHED are the unfixed originals'
Write-Host '  -- restoring them brings the "Missing Modules" error back, as intended.'

if (-not (Confirm-Step '  Restore the backed-up plugin manifests now?')) {
    Write-Host ''
    Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

Write-Host ''
Write-Host '  Restoring...' -NoNewline
$restored = 0
$failed   = @()
foreach ($item in $restorable) {
    try {
        Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
        $restored++
    } catch {
        $failed += $item.Relative
    }
}
Write-Host " done. $restored manifests restored." -ForegroundColor Green

if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host ("  {0} file(s) could not be written (read-only or in use):" -f $failed.Count) -ForegroundColor Yellow
    foreach ($name in ($failed | Select-Object -First 10)) {
        Write-Host "    $name" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
#  Verification
# ---------------------------------------------------------------------------

Write-Title 'VERIFICATION'

$after = @(Get-ManifestState $manifests)

Show-State -State $before -EditorId $editorId -Caption 'BEFORE'
Show-State -State $after  -EditorId $editorId -Caption 'AFTER'

$changed = @()
foreach ($entry in $before) {
    $now = ($after | Where-Object { $_.Path -eq $entry.Path }).BuildId
    if ($now -ne $entry.BuildId) {
        $changed += [pscustomobject]@{ Path = $entry.Path; Old = $entry.BuildId; New = $now }
    }
}

if ($changed.Count -gt 0) {
    Write-Host ''
    Write-Host '  Sample of restored files:' -ForegroundColor Cyan
    foreach ($entry in ($changed | Select-Object -First 3)) {
        Write-Host ''
        Write-Host ('    ' + $entry.Path.Substring($Engine.Length).TrimStart('\'))
        Write-Host ("      before : {0}" -f $entry.Old) -ForegroundColor Yellow
        Write-Host ("      after  : {0}" -f $entry.New) -ForegroundColor Green
    }
}

Write-Host ''
Write-Rule
if ($failed.Count -eq 0) {
    Write-Host ("  RESULT: PASS - {0} manifests restored, {1} changed back." -f $restored, $changed.Count) -ForegroundColor Green
    Write-Rule
    Write-Host ''
    Write-Host '  Your install now matches the backup. If the backup was taken before'
    Write-Host '  the fix, the mismatched build IDs shown above are expected.'
} else {
    Write-Host ("  RESULT: {0} file(s) failed to restore." -f $failed.Count) -ForegroundColor Yellow
    Write-Rule
    Write-Host ''
    Write-Host '  Close the editor and any file explorer windows, then run this again.'
}
Write-Host ''
