# Librarian Setup Script (Windows/PowerShell)
# Detects OS and writes hook configuration to .claude/settings.local.json
# Uses $env:CLAUDE_PLUGIN_ROOT to locate hook scripts within the plugin.

$ErrorActionPreference = "Stop"

# When run from the plugin, CLAUDE_PLUGIN_ROOT is set automatically.
# When run manually, derive from script location.
if (-not $env:CLAUDE_PLUGIN_ROOT) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $env:CLAUDE_PLUGIN_ROOT = (Resolve-Path (Join-Path $scriptDir "..")).Path
}

# Project dir
if ($env:CLAUDE_PROJECT_DIR) {
    $projectDir = $env:CLAUDE_PROJECT_DIR
} else {
    $projectDir = Get-Location
}

$settingsFile = Join-Path $projectDir ".claude\settings.local.json"
New-Item -ItemType Directory -Path (Join-Path $projectDir ".claude") -Force | Out-Null

Write-Host "Librarian Setup"
Write-Host "==============="
Write-Host "Project: $projectDir"
Write-Host "Plugin:  $($env:CLAUDE_PLUGIN_ROOT)"
Write-Host ""

# Determine hook commands based on OS
if ($IsWindows -or $env:OS -eq "Windows_NT") {
    $readCmd = 'powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/librarian-read.ps1"'
    $writeCmd = 'powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/librarian-write.ps1"'
    Write-Host "Detected Windows -- using .ps1 scripts"
} else {
    $readCmd = '${CLAUDE_PLUGIN_ROOT}/scripts/librarian-read.sh'
    $writeCmd = '${CLAUDE_PLUGIN_ROOT}/scripts/librarian-write.sh'
    Write-Host "Detected macOS/Linux -- using .sh scripts"
}

# Read existing settings or start fresh
$existing = @{}
if (Test-Path $settingsFile) {
    $existing = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable
    Write-Host "Found existing settings.local.json -- merging hooks"
} else {
    Write-Host "No existing settings.local.json -- creating new"
}

# Build hook configuration
$hookConfig = @{
    PreToolUse = @(
        @{
            matcher = "Edit|Write"
            hooks = @(
                @{
                    type = "command"
                    command = $readCmd
                    timeout = 5
                }
            )
        }
    )
    Stop = @(
        @{
            matcher = ""
            hooks = @(
                @{
                    type = "command"
                    command = $writeCmd
                    timeout = 15
                }
            )
        }
    )
}

# Merge hooks into existing settings
$existing["hooks"] = $hookConfig

# Write settings file
$json = $existing | ConvertTo-Json -Depth 10
Set-Content -Path $settingsFile -Value $json

# Create _memory_library if it doesn't exist
$memoryLib = Join-Path $projectDir "_memory_library"
if (-not (Test-Path $memoryLib)) {
    New-Item -ItemType Directory -Path $memoryLib -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $memoryLib ".scratch.md") -Force | Out-Null
    Write-Host "Created _memory_library/ directory"
}

Write-Host ""
Write-Host "Hooks configured in: $settingsFile"
Write-Host ""
Write-Host "Pre-tool hook (Edit|Write): $readCmd"
Write-Host "Stop hook: $writeCmd"
Write-Host ""
Write-Host "Setup complete! The Librarian is now active."
