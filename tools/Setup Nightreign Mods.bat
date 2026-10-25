<# : Nightreign mod setup - Seamless Co-op + More Map Variations
@echo off
setlocal
set "NR_ROOT=%~dp0"
set "NR_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (Get-Content -LiteralPath $env:NR_SELF -Raw)"
echo.
pause
exit /b
#>

# ---------------------------------------------------------------------------
# What this does (nothing outside this list is touched):
#   1. Checks the game is closed and this folder is a sensible place
#   2. Finds the More Map Variations (or MMV + Weapons Merge) and Seamless Co-op zips
#   3. Backs up your Nightreign save into "Save Backups" in this folder
#   4. Extracts More Map Variations into "MMV" in this folder
#   5. Puts Seamless Co-op inside MMV's mod folder
#   6. Writes the shared launch file MMV_Seamless.me3
#   7. Copies your normal save to the Seamless save, only if you don't have one
#   8. Puts a "Nightreign (Modded)" shortcut on your desktop
# Running it again with newer zips updates everything in place.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$IsWin = $env:OS -eq 'Windows_NT'
try { $Host.UI.RawUI.WindowTitle = 'Nightreign Mod Setup' } catch {}

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Step($n, $msg) { Write-Host ''; Write-Host "[$n/8] $msg" -ForegroundColor Cyan }
function Ask($msg) {
    Write-Host ''
    $a = Read-Host "$msg (Y/N)"
    return ($a -match '^\s*y')
}

$root = ($env:NR_ROOT).TrimEnd('\', '/')
$stage = Join-Path $root 'MMV_installing'
$scStage = Join-Path $root '_seamless_tmp'
$final = Join-Path $root 'MMV'
$launchName = 'MMV_Seamless.me3'

function Cleanup {
    foreach ($p in @($stage, $scStage)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
function Fail($msg) {
    Cleanup
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    Write-Host 'Your game, your saves and any existing MMV folder were left as they were.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '  NIGHTREIGN MOD SETUP  -  Seamless Co-op + More Map Variations' -ForegroundColor Green
Write-Host "  Folder: $root" -ForegroundColor DarkGray

try {
    # ---- 1. Sanity checks -------------------------------------------------
    Step 1 'Checking things are ready'

    if (Get-Process -Name 'nightreign' -ErrorAction SilentlyContinue) {
        Fail 'Nightreign is running. Quit the game completely, then run this again.'
    }
    if ($root -match 'steamapps[\\/]common') {
        Fail 'This folder is inside the Steam game folder. Move it somewhere else, e.g. E:\games\nightreign-mods.'
    }
    if ($root -match 'OneDrive') {
        Say 'Warning: this folder is inside OneDrive. Syncing can corrupt mod files mid-game.' Yellow
        Say 'Better: move this folder to something like E:\games\nightreign-mods.' Yellow
        if (-not (Ask 'Continue here anyway?')) { Fail 'Cancelled. Move the folder out of OneDrive and run this again.' }
    }
    if ($IsWin) {
        $me3Ok = $false
        try { $me3Ok = Test-Path 'Registry::HKEY_CLASSES_ROOT\.me3' } catch {}
        if (-not $me3Ok) {
            Say 'ModEngine 3 does not look installed (Windows does not know what a .me3 file is).' Yellow
            Say 'Get it from github.com/garyttierney/me3/releases  ->  me3_installer.exe' Yellow
            if (-not (Ask 'Continue anyway? Only say Y if you are sure me3 is installed')) { Fail 'Install ModEngine 3, then run this again.' }
        }
    }
    Say 'OK' Green

    # ---- 2. Find the downloads ---------------------------------------------
    Step 2 'Looking for the two mod downloads in this folder'

    $all = Get-ChildItem -LiteralPath $root -File
    # Prefer the official 'More Map Variations and Weapons Mod Merge' build when it is present
    $mmvZip = $all | Where-Object { $_.Extension -eq '.zip' -and $_.Name -match 'map.?variation' } |
        Sort-Object @{ Expression = { $_.Name -match 'weapon' }; Descending = $true }, @{ Expression = 'LastWriteTime'; Descending = $true } |
        Select-Object -First 1
    $scZip = $all | Where-Object { $_.Extension -eq '.zip' -and $_.Name -match 'seamless' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $missing = @()
    if (-not $mmvZip) { $missing += '  - More Map Variations  (nexusmods.com/eldenringnightreign/mods/578)' }
    if (-not $scZip) { $missing += '  - Seamless Co-op       (nexusmods.com/eldenringnightreign/mods/3)' }
    if ($missing.Count) {
        $odd = $all | Where-Object { $_.Extension -in '.7z', '.rar' }
        $hint = ''
        if ($odd) { $hint = "`nFound $($odd.Name -join ', ') - this script needs the .zip downloads." }
        Fail ("Put these .zip downloads in this folder first:`n" + ($missing -join "`n") + $hint)
    }
    $mmvLabel = if ($mmvZip.Name -match 'weapon') { 'MMV + Weapons:' } else { 'MMV:          ' }
    Say "$mmvLabel $($mmvZip.Name)"
    Say "Seamless:      $($scZip.Name)"

    $needBytes = [int64]($mmvZip.Length * 2.5) + 300MB
    $free = $null
    try { $free = (Get-Item -LiteralPath $root).PSDrive.Free } catch {}
    if ($free -and $free -lt $needBytes) {
        Fail ("Not enough space on this drive. Need about {0:N1} GB free, have {1:N1} GB." -f ($needBytes / 1GB), ($free / 1GB))
    }

    # ---- 3. Back up the save -----------------------------------------------
    Step 3 'Backing up your Nightreign save'

    $saveRoot = if ($env:APPDATA) { Join-Path $env:APPDATA 'Nightreign' } else { $null }
    if ($saveRoot -and (Test-Path -LiteralPath $saveRoot)) {
        $bkParent = Join-Path $root 'Save Backups'
        New-Item -ItemType Directory -Force -Path $bkParent | Out-Null
        $bk = Join-Path $bkParent (Get-Date -Format 'yyyy-MM-dd_HHmmss')
        Copy-Item -LiteralPath $saveRoot -Destination $bk -Recurse
        $srcCount = @(Get-ChildItem -LiteralPath $saveRoot -Recurse -File).Count
        $dstCount = @(Get-ChildItem -LiteralPath $bk -Recurse -File).Count
        if ($dstCount -lt $srcCount) { Fail "Backup copied $dstCount of $srcCount files. Close anything using the save (Steam sync, the game) and retry." }
        Say "Backed up $dstCount files to: Save Backups\$(Split-Path $bk -Leaf)" Green
    } else {
        Say 'No Nightreign save found. Launch the normal game once first if you want your progress carried over.' Yellow
        $saveRoot = $null
    }

    # ---- 4. Extract MMV ----------------------------------------------------
    Step 4 'Extracting More Map Variations (about a minute)'

    Cleanup
    if ($IsWin) { Unblock-File -LiteralPath $mmvZip.FullName; Unblock-File -LiteralPath $scZip.FullName }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($mmvZip.FullName, $stage)

    $mmvProfile = Get-ChildItem -LiteralPath $stage -Recurse -Filter '*.me3' -File |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'mod') -PathType Container } |
        Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $mmvProfile) { Fail "Couldn't find MMV's 'mod' folder inside the zip. The download layout may have changed - tell Ken." }
    $mmvDir = $mmvProfile.DirectoryName
    $modDir = Join-Path $mmvDir 'mod'
    Say 'OK' Green

    # ---- 5. Seamless into mod\SeamlessCoop --------------------------------
    Step 5 'Adding Seamless Co-op'

    [System.IO.Compression.ZipFile]::ExtractToDirectory($scZip.FullName, $scStage)
    $dll = Get-ChildItem -LiteralPath $scStage -Recurse -Filter 'nrsc.dll' -File | Select-Object -First 1
    if (-not $dll) { Fail "No nrsc.dll inside the Seamless zip. Re-download Seamless Co-op from Nexus mod 3." }
    $scTarget = Join-Path $modDir 'SeamlessCoop'
    if (Test-Path -LiteralPath $scTarget) { Remove-Item -LiteralPath $scTarget -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $scTarget | Out-Null
    Copy-Item -Path (Join-Path $dll.DirectoryName '*') -Destination $scTarget -Recurse
    $scVer = $null
    try { $scVer = (Get-Item -LiteralPath (Join-Path $scTarget 'nrsc.dll')).VersionInfo.FileVersion } catch {}
    Say 'OK' Green

    # ---- 6. Launch file ----------------------------------------------------
    Step 6 'Writing the shared launch file'

    $toml = @'
profileVersion = "v1"
start_online = false

[[supports]]
game = "nightreign"

[[packages]]
id = "MMV"
path = 'mod'

[[natives]]
path = 'mod/SeamlessCoop/nrsc.dll'
load_early = true
'@
    [System.IO.File]::WriteAllText((Join-Path $mmvDir $launchName), ($toml -replace "`r?`n", "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    $stockProfiles = (Get-ChildItem -LiteralPath $mmvDir -Filter '*.me3' -File | Where-Object { $_.Name -ne $launchName }).Name -join ', '

    # swap the new install into place, only now that everything above worked
    if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Recurse -Force }
    Move-Item -LiteralPath $mmvDir -Destination $final
    Cleanup
    $launch = Join-Path $final $launchName
    Say "OK: MMV\$launchName" Green

    # ---- 7. Carry progress over --------------------------------------------
    Step 7 'Carrying your progress over to the Seamless save'

    if ($saveRoot) {
        $did = 0; $had = 0
        foreach ($d in Get-ChildItem -LiteralPath $saveRoot -Directory) {
            $sl2 = Join-Path $d.FullName 'NR0000.sl2'
            $co2 = Join-Path $d.FullName 'NR0000.co2'
            if (Test-Path -LiteralPath $co2) { $had++ }
            elseif (Test-Path -LiteralPath $sl2) { Copy-Item -LiteralPath $sl2 -Destination $co2; $did++ }
        }
        if ($did) { Say 'Copied your relics and unlocks into a new Seamless save.' Green }
        elseif ($had) { Say 'You already have a Seamless save - left it alone.' Green }
        else { Say 'No save file to copy. Seamless will start a fresh save.' Yellow }
    } else {
        Say 'Skipped (no save found).' Yellow
    }

    # ---- 8. Desktop shortcut -----------------------------------------------
    Step 8 'Making the desktop shortcut'

    if ($IsWin) {
        $desk = [Environment]::GetFolderPath('Desktop')
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut((Join-Path $desk 'Nightreign (Modded).lnk'))
        $lnk.TargetPath = $launch
        $lnk.WorkingDirectory = $final
        $lnk.Description = 'Nightreign with Seamless Co-op + More Map Variations'
        $lnk.Save()
        Say 'OK: "Nightreign (Modded)" is on your desktop.' Green
    } else {
        Say 'Skipped (not Windows).' Yellow
    }

    # ---- Done ---------------------------------------------------------------
    Write-Host ''
    Write-Host '  DONE. Open Steam, then double-click "Nightreign (Modded)" on your desktop.' -ForegroundColor Green
    Write-Host '  Launching Nightreign from Steam still gives you the normal, unmodded game.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Paste this in The Terror of Tana so we know we match:' -ForegroundColor Cyan
    Write-Host "    $mmvLabel $($mmvZip.BaseName)"
    $scLine = $scZip.BaseName
    if ($scVer) { $scLine += "   [nrsc.dll $scVer]" }
    Write-Host "    Seamless:      $scLine"
    Write-Host ''
    Write-Host '  You can delete the two .zip files now if you want the space back.' -ForegroundColor DarkGray
}
catch {
    Fail $_.Exception.Message
}
