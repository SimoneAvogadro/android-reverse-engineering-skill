# install.ps1 - Universal installer for reverse engineering skills
# Installs agent-specific instruction files for any supported AI coding agent.
#
# Usage:
#   .\install.ps1                              # Interactive mode
#   .\install.ps1 -Agent cursor                # Install for Cursor
#   .\install.ps1 -Agent all                   # Install for all agents
#   .\install.ps1 -Agent copilot -Target C:\MyProject  # Install into another project
#   .\install.ps1 -List                        # List available agents
#   .\install.ps1 -CheckDeps                   # Run dependency check only

param(
    [ValidateSet('claude', 'codex', 'opencode', 'cursor', 'copilot', 'cline', 'windsurf', 'roo', 'aider', 'all')]
    [string]$Agent = '',

    [string]$Target = '',

    [switch]$List,

    [switch]$CheckDeps,

    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Help ---
if ($Help) {
    Write-Host 'Reverse Engineering Skills - Universal Installer'
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  .\install.ps1                              Interactive mode (choose agent)'
    Write-Host '  .\install.ps1 -Agent <agent>               Install for a specific agent'
    Write-Host '  .\install.ps1 -Agent all                   Install for all agents'
    Write-Host '  .\install.ps1 -Agent <agent> -Target <dir> Install into another project'
    Write-Host '  .\install.ps1 -List                        List supported agents'
    Write-Host '  .\install.ps1 -CheckDeps                   Run dependency check only'
    Write-Host ''
    Write-Host 'Agents:'
    Write-Host '  claude    - Claude Code (.claude-plugin/)'
    Write-Host '  codex     - OpenAI Codex (AGENTS.md)'
    Write-Host '  opencode  - OpenCode (AGENTS.md)'
    Write-Host '  cursor    - Cursor IDE (.cursor/rules/*.mdc)'
    Write-Host '  copilot   - GitHub Copilot (.github/instructions/)'
    Write-Host '  cline     - Cline (.clinerules/)'
    Write-Host '  windsurf  - Windsurf (.windsurf/rules/)'
    Write-Host '  roo       - Roo Code (.roo/rules/)'
    Write-Host '  aider     - Aider (.aider.conf.yml)'
    Write-Host '  all       - Install for all agents at once'
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -Target <dir>   Target directory (default: current directory)'
    Write-Host '  -List           List all supported agents'
    Write-Host '  -CheckDeps      Run the dependency checker and exit'
    Write-Host '  -Help           Show this help message'
    exit 0
}

# --- Agent definitions ---
$Agents = [ordered]@{
    claude   = @{ Name = 'Claude Code';     Files = @('.claude-plugin/') }
    codex    = @{ Name = 'OpenAI Codex';    Files = @('AGENTS.md') }
    opencode = @{ Name = 'OpenCode';        Files = @('AGENTS.md') }
    cursor   = @{ Name = 'Cursor IDE';      Files = @('.cursor/rules/') }
    copilot  = @{ Name = 'GitHub Copilot';  Files = @('.github/copilot-instructions.md', '.github/instructions/') }
    cline    = @{ Name = 'Cline';           Files = @('.clinerules/') }
    windsurf = @{ Name = 'Windsurf';        Files = @('.windsurf/rules/') }
    roo      = @{ Name = 'Roo Code';        Files = @('.roo/rules/') }
    aider    = @{ Name = 'Aider';           Files = @('.aider.conf.yml', 'AGENTS.md') }
}

# --- List ---
if ($List) {
    Write-Host 'Supported AI Coding Agents:' -ForegroundColor Cyan
    Write-Host ''
    foreach ($key in $Agents.Keys) {
        $agentDef = $Agents[$key]
        $fileList = ($agentDef.Files -join ', ')
        Write-Host ('  {0,-12} {1,-20} -> {2}' -f $key, $agentDef.Name, $fileList)
    }
    Write-Host ''
    Write-Host '  all          All agents           -> installs everything'
    Write-Host ''
    Write-Host 'Usage: .\install.ps1 -Agent <agent>' -ForegroundColor Green
    exit 0
}

# --- Check deps function ---
function Invoke-DependencyCheck {
    Write-Host '=== Running Dependency Checks ===' -ForegroundColor Cyan
    Write-Host ''
    
    $missingDeps = @()

    Write-Host '--- Windows Dependencies ---' -ForegroundColor Yellow
    $winCheck = Join-Path $ScriptDir 'plugins\windows-reverse-engineering\skills\windows-reverse-engineering\scripts\check-deps.ps1'
    $winInstall = Join-Path $ScriptDir 'plugins\windows-reverse-engineering\skills\windows-reverse-engineering\scripts\install-dep.ps1'
    if (Test-Path $winCheck) {
        $winOut = & powershell -ExecutionPolicy Bypass -File $winCheck
        foreach ($line in $winOut) {
            $lineStr = [string]$line
            if ($lineStr -match '^INSTALL_') {
                $depInfo = @{
                    OS = 'Windows'
                    Name = ($lineStr -split ':')[1]
                    InstallScript = $winInstall
                }
                $missingDeps += $depInfo
            } else {
                Write-Host $lineStr
            }
        }
    } else {
        Write-Host ('Windows check-deps.ps1 not found at: ' + $winCheck) -ForegroundColor Red
    }

    Write-Host ''
    Write-Host '--- Android Dependencies ---' -ForegroundColor Yellow
    $androidCheck = Join-Path $ScriptDir 'plugins\android-reverse-engineering\skills\android-reverse-engineering\scripts\check-deps.sh'
    $androidInstall = Join-Path $ScriptDir 'plugins\android-reverse-engineering\skills\android-reverse-engineering\scripts\install-dep.sh'
    if (Test-Path $androidCheck) {
        $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
        if ($bashCmd) {
            $andOut = & bash $androidCheck
            foreach ($line in $andOut) {
                $lineStr = [string]$line
                if ($lineStr -match '^INSTALL_') {
                    $depInfo = @{
                        OS = 'Android'
                        Name = ($lineStr -split ':')[1]
                        InstallScript = $androidInstall
                    }
                    $missingDeps += $depInfo
                } else {
                    Write-Host $lineStr
                }
            }
        } else {
            Write-Host 'bash not found. Android dependency check requires WSL or Git Bash.' -ForegroundColor Yellow
        }
    } else {
        Write-Host ('Android check-deps.sh not found at: ' + $androidCheck) -ForegroundColor Red
    }

    if ($missingDeps.Count -gt 0) {
        Write-Host ''
        $totalMissing = $missingDeps.Count
        $ans = Read-Host ('Detected {0} missing dependencies (optional/required). Would you like to install them now? (y/N)' -f $totalMissing)
        if ($ans -match '^y') {
            Write-Host ''
            foreach ($depInfo in $missingDeps) {
                Write-Host ('--- Installing ' + $depInfo.OS + ' dependency: ' + $depInfo.Name + ' ---') -ForegroundColor Cyan
                if ($depInfo.OS -eq 'Windows') {
                    & powershell -ExecutionPolicy Bypass -File $depInfo.InstallScript $depInfo.Name
                } else {
                    & bash $depInfo.InstallScript $depInfo.Name
                }
            }
            Write-Host ''
            Write-Host 'Done installing dependencies.' -ForegroundColor Green
            Write-Host 'Restart your terminal if any PATH variables were updated.' -ForegroundColor Yellow
        }
    }
}

if ($CheckDeps) {
    Invoke-DependencyCheck
    exit 0
}

# --- Interactive mode ---
if (-not $Agent) {
    Write-Host '+------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host '|   Reverse Engineering Skills - Universal Installer    |' -ForegroundColor Cyan
    Write-Host '+------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Which AI coding agent do you use?' -ForegroundColor Yellow
    Write-Host ''
    $i = 1
    $agentKeys = @($Agents.Keys)
    foreach ($key in $agentKeys) {
        Write-Host ('  [{0}] {1,-12} ({2})' -f $i, $key, $Agents[$key].Name)
        $i++
    }
    Write-Host ('  [{0}] all          (Install for all agents)' -f $i)
    Write-Host ''

    $choice = Read-Host 'Enter number or agent name'

    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $agentKeys.Count) {
            $Agent = $agentKeys[$idx]
        } elseif ($idx -eq $agentKeys.Count) {
            $Agent = 'all'
        } else {
            Write-Host 'Invalid choice.' -ForegroundColor Red
            exit 1
        }
    } else {
        $Agent = $choice.ToLower().Trim()
    }
}

# --- Target directory ---
if (-not $Target) {
    $Target = Get-Location
}

if (-not (Test-Path $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

$Target = (Resolve-Path $Target).Path

# --- Determine which agents to install ---
if ($Agent -eq 'all') {
    $installAgents = @($Agents.Keys)
} else {
    if (-not $Agents.ContainsKey($Agent)) {
        Write-Host ('Unknown agent: ' + $Agent) -ForegroundColor Red
        Write-Host 'Run: .\install.ps1 -List' -ForegroundColor Yellow
        exit 1
    }
    $installAgents = @($Agent)
}

Write-Host ''
Write-Host '=== Installing Reverse Engineering Skills ===' -ForegroundColor Cyan
Write-Host ('Target: ' + $Target) -ForegroundColor DarkGray
Write-Host ('Agents: ' + ($installAgents -join ', ')) -ForegroundColor DarkGray
Write-Host ''

# --- Copy helper ---
function Copy-SkillFile {
    param([string]$RelPath, [string]$SourceBase, [string]$DestBase)
    $src = Join-Path $SourceBase $RelPath
    $dst = Join-Path $DestBase $RelPath

    if (-not (Test-Path $src)) {
        Write-Host ('  [SKIP] ' + $RelPath + ' (source not found)') -ForegroundColor Yellow
        return $false
    }

    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    if (Test-Path $src -PathType Container) {
        Copy-Item -Path $src -Destination $dst -Recurse -Force
        Write-Host ('  [DIR]  ' + $RelPath) -ForegroundColor Green
    } else {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host ('  [FILE] ' + $RelPath) -ForegroundColor Green
    }
    return $true
}

# --- Always copy the plugins directory (core scripts + references) ---
$isLocal = ($Target -eq (Resolve-Path $ScriptDir).Path)

if (-not $isLocal) {
    Write-Host 'Copying core plugins...' -ForegroundColor Yellow
    Copy-SkillFile 'plugins' $ScriptDir $Target | Out-Null
}

# --- Install per-agent files ---
$copiedAgents = @()
$copiedFiles = @()

foreach ($agentKey in $installAgents) {
    $agentInfo = $Agents[$agentKey]
    Write-Host ''
    Write-Host ('Installing for ' + $agentInfo.Name + '...') -ForegroundColor Yellow

    foreach ($filePath in $agentInfo.Files) {
        if ($filePath.EndsWith('/')) {
            $dirPath = $filePath.TrimEnd('/')
            $src = Join-Path $ScriptDir $dirPath
            if (Test-Path $src) {
                Copy-SkillFile $dirPath $ScriptDir $Target | Out-Null
                $copiedFiles += $dirPath
            } else {
                Write-Host ('  [SKIP] ' + $dirPath + ' (not found in source)') -ForegroundColor Yellow
            }
        } else {
            $src = Join-Path $ScriptDir $filePath
            if (Test-Path $src) {
                if ($filePath -notin $copiedFiles) {
                    Copy-SkillFile $filePath $ScriptDir $Target | Out-Null
                    $copiedFiles += $filePath
                } else {
                    Write-Host ('  [SKIP] ' + $filePath + ' (already copied)') -ForegroundColor DarkGray
                }
            } else {
                Write-Host ('  [SKIP] ' + $filePath + ' (not found in source)') -ForegroundColor Yellow
            }
        }
    }
    $copiedAgents += $agentInfo.Name
}

# --- Summary ---
Write-Host ''
Write-Host '=== Installation Complete ===' -ForegroundColor Green
Write-Host ''
Write-Host ('Installed for: ' + ($copiedAgents -join ', ')) -ForegroundColor Cyan
Write-Host ('Location: ' + $Target) -ForegroundColor Cyan
Write-Host ''

# --- Next steps ---
Write-Host 'Next steps:' -ForegroundColor Yellow
Write-Host ''

if ('codex' -in $installAgents -or 'opencode' -in $installAgents -or 'all' -eq $Agent) {
    Write-Host '  Codex/OpenCode: AGENTS.md is automatically detected. Just start your agent.' -ForegroundColor DarkGray
}
if ('cursor' -in $installAgents -or 'all' -eq $Agent) {
    Write-Host '  Cursor: Rules in .cursor/rules/ are auto-loaded. Open the project in Cursor.' -ForegroundColor DarkGray
}
if ('copilot' -in $installAgents -or 'all' -eq $Agent) {
    Write-Host '  Copilot: Instructions in .github/ are auto-loaded in VS Code/GitHub.' -ForegroundColor DarkGray
}
if ('cline' -in $installAgents -or 'all' -eq $Agent) {
    Write-Host '  Cline: Rules in .clinerules/ are auto-loaded. Open project in VS Code with Cline.' -ForegroundColor DarkGray
}
if ('windsurf' -in $installAgents -or 'all' -eq $Agent) {
    Write-Host '  Windsurf: Rules in .windsurf/rules/ are auto-loaded. Open project in Windsurf.' -ForegroundColor DarkGray
}
if ('roo' -in $installAgents -or 'all' -eq $Agent) {
    Write-Host '  Roo Code: Rules in .roo/rules/ are auto-loaded. Open project in VS Code with Roo.' -ForegroundColor DarkGray
}
if ('aider' -in $installAgents -or 'all' -eq $Agent) {
    Write-Host '  Aider: .aider.conf.yml auto-loads AGENTS.md. Just run aider in the project.' -ForegroundColor DarkGray
}
if ('claude' -in $installAgents -or 'all' -eq $Agent) {
    Write-Host '  Claude Code: Plugin is auto-detected from .claude-plugin/. Just open the project.' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Run dependency check:' -ForegroundColor Yellow
Write-Host '  .\install.ps1 -CheckDeps' -ForegroundColor White
Write-Host ''
