$ErrorActionPreference = 'Stop'

$packages = @(
    'Git.Git', 'Kitware.CMake', 'Ninja-build.Ninja', 'LLVM.clangd',
    'Arm.GnuArmEmbeddedToolchain', 'xpack-dev-tools.openocd-xpack',
    'BrechtSanders.WinLibs.POSIX.UCRT'
)

$userKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
$machineKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
$raw = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
$originalUser = [string]$userKey.GetValue('Path', '', $raw)
$originalMachine = [string]$machineKey.GetValue('Path', '', $raw)
$originalSession = [string]$env:Path
$originalKind = if ($userKey.GetValueNames() -contains 'Path') { $userKey.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
$backupDir = Join-Path $env:LOCALAPPDATA 'RPL\PathBackups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$backup = Join-Path $backupDir ('path-' + [Guid]::NewGuid().ToString('N') + '.json')
@{ UserPath = $originalUser; UserPathKind = "$originalKind"; MachinePath = $originalMachine; SessionPath = $originalSession } |
    ConvertTo-Json | Set-Content -LiteralPath $backup -Encoding UTF8

function Merge-Path([string]$Base, [string[]]$Entries) {
    foreach ($entry in $Entries) {
        if ($entry -and (($Base -split ';') -cnotcontains $entry)) {
            if ($Base -and -not $Base.EndsWith(';')) { $Base += ';' }
            $Base += $entry
        }
    }
    return $Base
}

function Get-PersistentPath {
    $machine = [string]$machineKey.GetValue('Path', '', $raw)
    $user = [string]$userKey.GetValue('Path', '', $raw)
    return [Environment]::ExpandEnvironmentVariables("$machine;$user")
}

$windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
$winget = Join-Path $windowsApps 'winget.exe'
if (-not (Test-Path -LiteralPath $winget -PathType Leaf)) {
    $winget = (Get-Command winget.exe -CommandType Application).Source
}

$state = @{ User = $originalUser; Changed = $false }
function Protect-UserPath([string[]]$Extra = @()) {
    $current = [string]$userKey.GetValue('Path', '', $raw)
    $currentKind = if ($userKey.GetValueNames() -contains 'Path') { $userKey.GetValueKind('Path') } else { $originalKind }
    $desired = Merge-Path $state.User (@($current -split ';') + $Extra)
    $kind = $currentKind
    if ($originalKind -eq 'ExpandString' -or $currentKind -eq 'ExpandString') {
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    }
    if ($current -cne $desired -or $currentKind -ne $kind) {
        $userKey.SetValue('Path', $desired, $kind)
        $state.Changed = $true
    }
    $state.User = $desired
    $env:Path = Merge-Path $env:Path ((Get-PersistentPath) -split ';')
}

function Assert-MachinePath {
    $current = [string]$machineKey.GetValue('Path', '', $raw)
    $missing = @($originalMachine -split ';' | Where-Object { $_ -and (($current -split ';') -cnotcontains $_) })
    if ($missing.Count) { throw "An installer changed existing system PATH entries. Review $backup before continuing." }
}

# Temporarily use TAR extraction, restoring the original file byte-for-byte.
$settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json'
$settingsBackup = "$settings.rpl-backup"
if (Test-Path -LiteralPath $settingsBackup) { throw "Existing WinGet settings backup: $settingsBackup. Review it before retrying." }
$hadSettings = Test-Path -LiteralPath $settings
if ($hadSettings) { Copy-Item -LiteralPath $settings -Destination $settingsBackup }

try {
    New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null
    '{"installBehavior":{"archiveExtractionMethod":"tar"}}' | Set-Content -LiteralPath $settings -Encoding Ascii
    foreach ($package in $packages) {
        try {
            & $winget install --id $package --exact --source winget --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -notin @(0, -1978335189)) {
                Write-Warning "Check installation of $package ($LASTEXITCODE)."
            }
        } finally {
            Protect-UserPath
            Assert-MachinePath
        }
    }

    # SerialScope is distributed through the Microsoft Store, not winget source.
    try {
        & $winget install --id 9NSVHTVWKC2X --exact --source msstore --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -notin @(0, -1978335189)) {
            throw "Check installation of SerialScope ($LASTEXITCODE)."
        }
    } finally {
        Protect-UserPath
        Assert-MachinePath
    }
} finally {
    try {
        if ($hadSettings) { Copy-Item -LiteralPath $settingsBackup -Destination $settings -Force; Remove-Item -LiteralPath $settingsBackup }
        elseif (Test-Path -LiteralPath $settings) { Remove-Item -LiteralPath $settings }
    } finally {
        Protect-UserPath
    }
}

$extra = @()
$persistent = Get-PersistentPath
if (($persistent -split ';') -notcontains $windowsApps -and (Test-Path -LiteralPath $windowsApps)) {
    $extra += $windowsApps
}

# Locate clangd in WinGet's actual package directories if it isn't on PATH.
$clangdOnPath = @($persistent -split ';' | Where-Object {
    $_ -and (Test-Path -LiteralPath ($_.Trim('"') + '\clangd.exe') -PathType Leaf -ErrorAction SilentlyContinue)
})
if (-not $clangdOnPath.Count) {
    $clangd = Get-ChildItem -LiteralPath @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
        "$env:ProgramFiles\WinGet\Packages"
    ) -Filter clangd.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*\LLVM.clangd_*\*' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($clangd) { $extra += $clangd.DirectoryName; Write-Host "Adding clangd: $($clangd.DirectoryName)" }
}
Protect-UserPath $extra
Assert-MachinePath

$finalUser = [string]$userKey.GetValue('Path', '', $raw)
if ($originalUser -and -not $finalUser.StartsWith($originalUser, [StringComparison]::Ordinal)) {
    throw "Original user PATH not preserved. Review $backup."
}

$tools = 'winget', 'git', 'cmake', 'ninja', 'clangd', 'gcc', 'g++', 'arm-none-eabi-gcc', 'arm-none-eabi-g++', 'arm-none-eabi-gdb', 'arm-none-eabi-objcopy', 'arm-none-eabi-size', 'openocd'
$session = $env:Path
try {
    $env:Path = Get-PersistentPath
    $missing = foreach ($tool in $tools) {
        $cmd = Get-Command "$tool.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { Write-Host "[OK] $tool - $($cmd.Source)" -ForegroundColor Green }
        else { Write-Host "[MISSING] $tool" -ForegroundColor Red; $tool }
    }
} finally { $env:Path = $session }
if ($state.Changed) { Write-Host 'Sign out and back in to ensure all Windows applications receive the updated PATH.' }
if ($missing) { throw "Missing tools: $($missing -join ', ')" }
Write-Host 'Setup complete. You are ready to build and flash.'
