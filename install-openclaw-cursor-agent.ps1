[CmdletBinding()]
param(
    [string]$OpenClawHome = (Join-Path $env:USERPROFILE ".openclaw"),
    [string]$ConfigPath = "D:\project\openclaw\openclaw.json",
    [switch]$NoConfigUpdate
)

$ErrorActionPreference = "Stop"

function Write-Title([string]$Text) {
    Write-Host "============================================================"
    Write-Host $Text
    Write-Host "============================================================"
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] $Value
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Ensure-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string]$Name
    )

    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{})
    }

    return $Object.$Name
}

function Ensure-StringArray {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string]$Name
    )

    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue @()
    }

    $value = @($Object.$Name)
    $Object.$Name = $value
    return $Object.$Name
}

function Add-UniqueString {
    param(
        [Parameter(Mandatory = $true)] [object[]]$Array,
        [Parameter(Mandatory = $true)] [string]$Value
    )

    if ($Array -contains $Value) {
        return ,$Array
    }

    return ,($Array + $Value)
}

function Copy-DirectoryContent {
    param(
        [Parameter(Mandatory = $true)] [string]$Source,
        [Parameter(Mandatory = $true)] [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginSource = Join-Path $RepoRoot "extensions\openclaw-cursor-agent"
$ToolkitSource = Join-Path $RepoRoot "cursor-agent-system"
$PluginInstallPath = Join-Path $OpenClawHome "workspace\plugins\openclaw-cursor-agent"
$ToolkitInstallPath = Join-Path $OpenClawHome "workspace\cursor-agent-system"
$PluginId = "openclaw-cursor-agent"

if (-not (Test-Path -LiteralPath $PluginSource)) {
    throw "找不到插件源目录: $PluginSource"
}

if (-not (Test-Path -LiteralPath $ToolkitSource)) {
    throw "找不到工具源目录: $ToolkitSource"
}

$WslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
$BashCommand = Get-Command bash.exe -ErrorAction SilentlyContinue

$ExecutionMode = "wsl"
$ShellExecutable = "C:\Windows\System32\wsl.exe"
$PluginEnabled = $false
$Warnings = @()

if ($WslCommand) {
    $ExecutionMode = "wsl"
    $ShellExecutable = $WslCommand.Source
    $PluginEnabled = $true
} elseif ($BashCommand) {
    $ExecutionMode = "direct"
    $ShellExecutable = $BashCommand.Source
    $PluginEnabled = $true
    $Warnings += "检测到 bash.exe，但未检测到 wsl.exe。请确认该 bash 环境内已经安装 tmux 和 Cursor CLI。"
} else {
    $Warnings += "当前环境未检测到 wsl.exe 或 bash.exe。插件文件会安装，但默认保持 disabled，待你装好 WSL/Git Bash 后再启用。"
}

Write-Title "安装 OpenClaw Cursor Agent 插件"
Write-Host "仓库根目录:      $RepoRoot"
Write-Host "OpenClawHome:    $OpenClawHome"
Write-Host "插件安装目录:    $PluginInstallPath"
Write-Host "工具安装目录:    $ToolkitInstallPath"
Write-Host "配置文件:        $ConfigPath"
Write-Host "执行模式:        $ExecutionMode"
Write-Host "Shell 可执行文件: $ShellExecutable"
Write-Host "插件启用状态:    $PluginEnabled"
Write-Host ""

New-Item -ItemType Directory -Force -Path (Join-Path $OpenClawHome "workspace") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OpenClawHome "workspace\plugins") | Out-Null

Copy-DirectoryContent -Source $PluginSource -Destination $PluginInstallPath
Copy-DirectoryContent -Source $ToolkitSource -Destination $ToolkitInstallPath

Write-Host "已复制插件目录。"
Write-Host "已复制 cursor-agent-system 工具目录。"
Write-Host ""

if (-not $NoConfigUpdate) {
    if (Test-Path -LiteralPath $ConfigPath) {
        $RawConfig = Get-Content -LiteralPath $ConfigPath -Raw
        $Config = if ([string]::IsNullOrWhiteSpace($RawConfig)) { [pscustomobject]@{} } else { $RawConfig | ConvertFrom-Json }
    } else {
        $Config = [pscustomobject]@{}
    }

    $Plugins = Ensure-ObjectProperty -Object $Config -Name "plugins"
    $Allow = Ensure-StringArray -Object $Plugins -Name "allow"
    $Plugins.allow = Add-UniqueString -Array $Allow -Value $PluginId

    $Load = Ensure-ObjectProperty -Object $Plugins -Name "load"
    $LoadPaths = Ensure-StringArray -Object $Load -Name "paths"
    $PluginPathNormalized = ($PluginInstallPath -replace "\\", "/")
    $Load.paths = Add-UniqueString -Array $LoadPaths -Value $PluginPathNormalized

    $Entries = Ensure-ObjectProperty -Object $Plugins -Name "entries"
    $EntryConfig = [pscustomobject]@{
        enabled = $PluginEnabled
        config = [pscustomobject]@{
            toolkitRoot = ($ToolkitInstallPath -replace "\\", "/")
            defaultProjectPath = ($RepoRoot -replace "\\", "/")
            executionMode = $ExecutionMode
            timeoutMs = 120000
            shell = [pscustomobject]@{
                executable = ($ShellExecutable -replace "\\", "/")
                args = @()
                workingDirectory = ""
                wslDistro = ""
            }
        }
    }
    Set-ObjectProperty -Object $Entries -Name $PluginId -Value $EntryConfig

    $JsonText = $Config | ConvertTo-Json -Depth 30
    Set-Content -LiteralPath $ConfigPath -Value $JsonText -Encoding UTF8
    Write-Host "已更新配置文件: $ConfigPath"
} else {
    Write-Host "已跳过配置文件更新。"
}

Write-Host ""
Write-Title "安装完成"
Write-Host "你现在可以参考以下命令："
Write-Host "  openclaw cursor-agent-doctor"
Write-Host "  openclaw cursor-agent-list"
Write-Host "  /cursor doctor"
Write-Host "  /cursor list"
Write-Host ""

if ($Warnings.Count -gt 0) {
    Write-Host "注意事项："
    foreach ($Warning in $Warnings) {
        Write-Host "  - $Warning"
    }
    Write-Host ""
}

Write-Host "示例配置文件："
Write-Host "  $PluginSource\examples\openclaw.json.windows.example.json"
