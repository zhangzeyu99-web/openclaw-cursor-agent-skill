[CmdletBinding()]
param(
    [string]$OpenClawHome = (Join-Path $env:USERPROFILE ".openclaw"),
    [string]$ConfigPath = "D:\project\openclaw\openclaw.json",
    [string]$DefaultProjectPath = "",
    [switch]$PreferGitBash,
    [switch]$SkipTmuxBootstrap,
    [switch]$SkipAgentBootstrap,
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

function Invoke-HttpDownload {
    param(
        [Parameter(Mandatory = $true)] [string]$Url,
        [Parameter(Mandatory = $true)] [string]$Destination
    )

    Invoke-WebRequest -Uri $Url -OutFile $Destination
}

function Get-GitBashRoot {
    $GitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $GitCommand) {
        return $null
    }

    $GitCmdDir = Split-Path -Parent $GitCommand.Source
    $GitRoot = Split-Path -Parent $GitCmdDir
    $BashCandidates = @(
        (Join-Path $GitRoot "bin\bash.exe"),
        (Join-Path $GitRoot "usr\bin\bash.exe")
    )

    foreach ($Candidate in $BashCandidates) {
        if (Test-Path -LiteralPath $Candidate) {
            return $GitRoot
        }
    }

    return $null
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)] [string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [string]$Content
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Test-BashCommand {
    param(
        [Parameter(Mandatory = $true)] [string]$BashExe,
        [Parameter(Mandatory = $true)] [string]$CommandText
    )

    $Output = & $BashExe -lc $CommandText 2>$null
    return @{
        Success = ($LASTEXITCODE -eq 0)
        Output = ($Output -join "`n")
        ExitCode = $LASTEXITCODE
    }
}

function Install-CursorAgentWindows {
    param([Parameter(Mandatory = $true)] [ref]$Warnings)

    $AgentCommand = Get-Command agent -ErrorAction SilentlyContinue
    if ($AgentCommand) {
        return
    }

    try {
        Invoke-Expression (Invoke-RestMethod "https://cursor.com/install?win32=true")
    } catch {
        $Warnings.Value += "自动安装 Cursor CLI 失败：$($_.Exception.Message)"
    }
}

function Ensure-GitBashWrapper {
    param(
        [Parameter(Mandatory = $true)] [string]$GitRoot,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [string]$Target
    )

    $WrapperPath = Join-Path $GitRoot "usr\bin\$Name"
    $Content = @"
#!/usr/bin/env bash
exec powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$Target" "`$@"
"@
    Write-Utf8NoBomFile -Path $WrapperPath -Content $Content
}

function Ensure-GitBashPythonWrapper {
    param([Parameter(Mandatory = $true)] [string]$GitRoot)

    $WrapperPath = Join-Path $GitRoot "usr\bin\python3"
    $Content = @"
#!/usr/bin/env bash
exec python.exe "`$@"
"@
    Write-Utf8NoBomFile -Path $WrapperPath -Content $Content
}

function Expand-MsysPackage {
    param(
        [Parameter(Mandatory = $true)] [string]$PackagePath,
        [Parameter(Mandatory = $true)] [string]$Destination,
        [string[]]$Members = @()
    )

    $PythonScript = @'
import os
import sys
import tarfile

package_path = sys.argv[1]
destination = sys.argv[2]
members = sys.argv[3:]

with tarfile.open(package_path, "r:*") as tf:
    if members:
        selected = [m for m in tf.getmembers() if m.name in members]
        tf.extractall(destination, members=selected)
    else:
        tf.extractall(destination)
'@

    & python -c $PythonScript $PackagePath $Destination @Members
    if ($LASTEXITCODE -ne 0) {
        throw "解压失败: $PackagePath"
    }
}

function Install-TmuxForGitBash {
    param(
        [Parameter(Mandatory = $true)] [string]$GitRoot,
        [Parameter(Mandatory = $true)] [string]$BashExe,
        [Parameter(Mandatory = $true)] [ref]$Warnings
    )

    $Probe = Test-BashCommand -BashExe $BashExe -CommandText 'tmux -V >/dev/null 2>&1'
    if ($Probe.Success) {
        return
    }

    $TempDir = Join-Path $env:TEMP "openclaw-cursor-agent-msys2"
    Ensure-Directory -Path $TempDir

    $LibeventUrl = "https://mirror.msys2.org/msys/x86_64/libevent-2.1.12-4-x86_64.pkg.tar.zst"
    $TmuxUrl = "https://repo.msys2.org/msys/x86_64/tmux-3.5.a-1-x86_64.pkg.tar.zst"
    $LibeventPath = Join-Path $TempDir "libevent-2.1.12-4-x86_64.pkg.tar.zst"
    $TmuxPath = Join-Path $TempDir "tmux-3.5.a-1-x86_64.pkg.tar.zst"

    Invoke-HttpDownload -Url $LibeventUrl -Destination $LibeventPath
    Invoke-HttpDownload -Url $TmuxUrl -Destination $TmuxPath

    Expand-MsysPackage -PackagePath $LibeventPath -Destination $GitRoot
    Expand-MsysPackage -PackagePath $TmuxPath -Destination $GitRoot -Members @(
        "usr/bin/tmux.exe",
        "usr/share/man/man1/tmux.1.gz",
        "usr/share/licenses/tmux/COPYING"
    )

    $ProbeAfter = Test-BashCommand -BashExe $BashExe -CommandText 'tmux -V >/dev/null 2>&1'
    if (-not $ProbeAfter.Success) {
        $Warnings.Value += "tmux 兼容包已写入 Git Bash，但自检仍未通过，请手动检查 Git 运行时兼容性。"
    }
}

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginSource = Join-Path $RepoRoot "extensions\openclaw-cursor-agent"
$ToolkitSource = Join-Path $RepoRoot "cursor-agent-system"
$PluginInstallPath = Join-Path $OpenClawHome "workspace\plugins\openclaw-cursor-agent"
$ToolkitInstallPath = Join-Path $OpenClawHome "workspace\cursor-agent-system"
$PluginId = "openclaw-cursor-agent"
$ResolvedDefaultProjectPath = if ([string]::IsNullOrWhiteSpace($DefaultProjectPath)) { $RepoRoot } else { $DefaultProjectPath }
$CursorAgentDir = Join-Path $env:LOCALAPPDATA "cursor-agent"

if (-not (Test-Path -LiteralPath $PluginSource)) {
    throw "找不到插件源目录: $PluginSource"
}

if (-not (Test-Path -LiteralPath $ToolkitSource)) {
    throw "找不到工具源目录: $ToolkitSource"
}

$WslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
$GitBashRoot = Get-GitBashRoot
$GitBashExe = if ($GitBashRoot) { Join-Path $GitBashRoot "bin\bash.exe" } else { $null }
$BashCommand = if ($GitBashExe -and (Test-Path -LiteralPath $GitBashExe)) { @{ Source = $GitBashExe } } else { Get-Command bash.exe -ErrorAction SilentlyContinue }

$ExecutionMode = "wsl"
$ShellExecutable = "C:\Windows\System32\wsl.exe"
$PluginEnabled = $false
$Warnings = @()

if ($PreferGitBash -and $GitBashExe) {
    $ExecutionMode = "direct"
    $ShellExecutable = $GitBashExe
    $PluginEnabled = $true
} elseif ($WslCommand) {
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
Ensure-Directory -Path (Join-Path $ToolkitInstallPath "status")
Ensure-Directory -Path (Join-Path $ToolkitInstallPath "tasks")
Ensure-Directory -Path (Join-Path $ToolkitInstallPath "logs")

Write-Host "已复制插件目录。"
Write-Host "已复制 cursor-agent-system 工具目录。"
Write-Host ""

if ($ExecutionMode -eq "direct" -and $GitBashRoot) {
    if (-not $SkipAgentBootstrap) {
        Install-CursorAgentWindows -Warnings ([ref]$Warnings)
    }

    Ensure-GitBashWrapper -GitRoot $GitBashRoot -Name "agent" -Target (($CursorAgentDir -replace "\\", "/") + "/agent.ps1")
    Ensure-GitBashWrapper -GitRoot $GitBashRoot -Name "cursor-agent" -Target (($CursorAgentDir -replace "\\", "/") + "/cursor-agent.ps1")
    Ensure-GitBashPythonWrapper -GitRoot $GitBashRoot

    if (-not $SkipTmuxBootstrap) {
        Install-TmuxForGitBash -GitRoot $GitBashRoot -BashExe $GitBashExe -Warnings ([ref]$Warnings)
    }
}

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
            defaultProjectPath = ($ResolvedDefaultProjectPath -replace "\\", "/")
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
