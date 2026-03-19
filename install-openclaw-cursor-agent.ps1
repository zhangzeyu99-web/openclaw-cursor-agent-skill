[CmdletBinding()]
param(
    [string]$OpenClawHome = (Join-Path $env:USERPROFILE ".openclaw"),
    [string]$DefaultProjectPath = "",
    [string]$WslDistro = "Debian",
    [switch]$NoConfigUpdate
)

$ErrorActionPreference = "Stop"

function Write-Title([string]$Text) {
    Write-Host "============================================================"
    Write-Host $Text
    Write-Host "============================================================"
}

function Set-ObjectProperty($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Ensure-ObjectProperty($Object, [string]$Name) {
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{})
    }
    return $Object.$Name
}

function Ensure-StringArray($Object, [string]$Name) {
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue @()
    }
    $Object.$Name = @($Object.$Name)
    return $Object.$Name
}

function Add-UniqueString([object[]]$Array, [string]$Value) {
    if ($Array -contains $Value) { return ,$Array }
    return ,($Array + $Value)
}

function Copy-DirectoryContent([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

# --- Main ---

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginSource = Join-Path $RepoRoot "extensions\openclaw-cursor-agent"
$ToolkitSource = Join-Path $RepoRoot "cursor-agent-system"
$PluginInstallPath = Join-Path $OpenClawHome "workspace\plugins\openclaw-cursor-agent"
$ToolkitInstallPath = Join-Path $OpenClawHome "workspace\cursor-agent-system"
$PluginId = "openclaw-cursor-agent"
$ResolvedProjectPath = if ([string]::IsNullOrWhiteSpace($DefaultProjectPath)) { $RepoRoot } else { $DefaultProjectPath }

if (-not (Test-Path -LiteralPath $PluginSource)) { throw "Plugin source not found: $PluginSource" }
if (-not (Test-Path -LiteralPath $ToolkitSource)) { throw "Toolkit source not found: $ToolkitSource" }

$WslExe = "C:\Windows\System32\wsl.exe"
$WslAvailable = Test-Path -LiteralPath $WslExe
$Warnings = @()

if (-not $WslAvailable) {
    $Warnings += "wsl.exe not found. Please install WSL and a Linux distro (e.g. Debian) first."
}

Write-Title "Installing OpenClaw Cursor Agent Plugin"
Write-Host "Repo root:     $RepoRoot"
Write-Host "Plugin dest:   $PluginInstallPath"
Write-Host "Toolkit dest:  $ToolkitInstallPath"
Write-Host "WSL distro:    $WslDistro"
Write-Host "WSL available: $WslAvailable"
Write-Host ""

# Copy plugin and toolkit
New-Item -ItemType Directory -Force -Path (Join-Path $OpenClawHome "workspace\plugins") | Out-Null
Copy-DirectoryContent -Source $PluginSource -Destination $PluginInstallPath
Copy-DirectoryContent -Source $ToolkitSource -Destination $ToolkitInstallPath

# Create runtime directories
foreach ($Dir in @("status", "tasks", "logs")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $ToolkitInstallPath $Dir) | Out-Null
}

Write-Host "Copied plugin and toolkit."
Write-Host ""

# Update openclaw.json
if (-not $NoConfigUpdate) {
    $ConfigPath = Join-Path $OpenClawHome "openclaw.json"
    if (Test-Path -LiteralPath $ConfigPath) {
        $Raw = Get-Content -LiteralPath $ConfigPath -Raw
        $Config = if ([string]::IsNullOrWhiteSpace($Raw)) { [pscustomobject]@{} } else { $Raw | ConvertFrom-Json }
    } else {
        $Config = [pscustomobject]@{}
    }

    $Plugins = Ensure-ObjectProperty -Object $Config -Name "plugins"
    $Plugins.allow = Add-UniqueString -Array (Ensure-StringArray -Object $Plugins -Name "allow") -Value $PluginId

    $Load = Ensure-ObjectProperty -Object $Plugins -Name "load"
    $Load.paths = Add-UniqueString -Array (Ensure-StringArray -Object $Load -Name "paths") -Value ($PluginInstallPath -replace "\\", "/")

    $Entries = Ensure-ObjectProperty -Object $Plugins -Name "entries"
    Set-ObjectProperty -Object $Entries -Name $PluginId -Value ([pscustomobject]@{
        enabled = $WslAvailable
        config = [pscustomobject]@{
            toolkitRoot = ($ToolkitInstallPath -replace "\\", "/")
            defaultProjectPath = ($ResolvedProjectPath -replace "\\", "/")
            executionMode = "wsl"
            timeoutMs = 120000
            shell = [pscustomobject]@{
                executable = ($WslExe -replace "\\", "/")
                args = @()
                workingDirectory = ""
                wslDistro = $WslDistro
            }
        }
    })

    $Config | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Write-Host "Updated config: $ConfigPath"
} else {
    Write-Host "Skipped config update."
}

Write-Host ""
Write-Title "Installation Complete"
Write-Host "Verify with:  openclaw cursor-agent-doctor"
Write-Host ""

if ($Warnings.Count -gt 0) {
    Write-Host "Warnings:"
    foreach ($W in $Warnings) { Write-Host "  - $W" }
    Write-Host ""
}
