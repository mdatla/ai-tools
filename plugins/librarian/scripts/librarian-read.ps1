# Librarian Pre-Tool Hook (Windows/PowerShell)
# Walks up _memory_library/ from the target file, injects context into Claude.

# --- Logging (set to $false to disable) ---
$LibrarianLogEnabled = $true
$LibrarianLogFile = Join-Path $env:USERPROFILE ".claude\librarian.log"

function Write-Log($msg) {
    if ($LibrarianLogEnabled) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LibrarianLogFile -Value "[$ts] [read] $msg"
    }
}

$ErrorActionPreference = "Stop"

$inputJson = [Console]::In.ReadToEnd()
Write-Log "Hook fired"

# Extract file_path — regex match from JSON
$filePath = ""
if ($inputJson -match '"file_path"\s*:\s*"([^"]*)"') {
    $filePath = $Matches[1]
}
if (-not $filePath) { Write-Log "No file_path found"; exit 0 }
Write-Log "File: $filePath"

# Walk up from file's directory to find nearest _memory_library/
$searchDir = Split-Path $filePath -Parent
$projectDir = $null
while ($searchDir) {
    $candidate = Join-Path $searchDir "_memory_library"
    if (Test-Path $candidate -PathType Container) {
        $projectDir = $searchDir
        break
    }
    $parent = Split-Path $searchDir -Parent
    if (-not $parent -or $parent -eq $searchDir) { break }
    $searchDir = $parent
}
if (-not $projectDir) { Write-Log "No _memory_library/ found"; exit 0 }

$memoryLib = Join-Path $projectDir "_memory_library"

# Compute relative path
$normalizedFile = $filePath.Replace("\", "/")
$normalizedProject = $projectDir.Replace("\", "/")
if (-not $normalizedFile.StartsWith($normalizedProject + "/")) { exit 0 }

$relPath = $normalizedFile.Substring($normalizedProject.Length + 1)
$relDir = Split-Path $relPath -Parent
if (-not $relDir) { $relDir = "" }

# Collect .md files walking up
$context = @()
$currentDir = $relDir
$visitedRoot = $false

while ($true) {
    if ($currentDir -eq "") {
        $mirrorDir = $memoryLib
        $displayPrefix = "global"
        $visitedRoot = $true
    } else {
        $mirrorDir = Join-Path $memoryLib $currentDir
        $displayPrefix = $currentDir
    }

    if (Test-Path $mirrorDir -PathType Container) {
        $mdFiles = Get-ChildItem -Path $mirrorDir -Filter "*.md" -File -ErrorAction SilentlyContinue
        foreach ($mdFile in $mdFiles) {
            if ($mdFile.Name -eq ".scratch.md") { continue }
            $content = Get-Content $mdFile.FullName -Raw
            $context += "--- [$displayPrefix/$($mdFile.Name)] ---`n$content"
        }
    }

    if ($currentDir -eq "") { break }
    $parentDir = Split-Path $currentDir -Parent
    if (-not $parentDir -or $parentDir -eq $currentDir) {
        $currentDir = ""
    } else {
        $currentDir = $parentDir
    }
}

# Read root if walk-up didn't reach it
if (-not $visitedRoot) {
    $rootMdFiles = Get-ChildItem -Path $memoryLib -Filter "*.md" -File -ErrorAction SilentlyContinue
    foreach ($mdFile in $rootMdFiles) {
        if ($mdFile.Name -eq ".scratch.md") { continue }
        $content = Get-Content $mdFile.FullName -Raw
        $context += "--- [global/$($mdFile.Name)] ---`n$content"
    }
}

# Output JSON with additionalContext
if ($context.Count -gt 0) {
    Write-Log "Injecting $($context.Count) files for $relPath"
    $fullContext = "[Librarian] Memory library context for ${relPath}:`n" + ($context -join "`n")
    # Escape for JSON
    $escaped = $fullContext.Replace('\', '\\').Replace('"', '\"').Replace("`r`n", '\n').Replace("`n", '\n').Replace("`t", '\t')
    Write-Output "{`"hookSpecificOutput`":{`"hookEventName`":`"PreToolUse`",`"permissionDecision`":`"allow`",`"additionalContext`":`"$escaped`"}}"
}

exit 0
