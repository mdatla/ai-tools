# Librarian Stop Hook (Windows/PowerShell)
# Phase 1: Syncs auto-memory -> .scratch.md
# Phase 2: Routes scratch entries -> library files via [TAG: path, type: file]

# --- Logging (set to $false to disable) ---
$LibrarianLogEnabled = $true
$LibrarianLogFile = Join-Path $env:USERPROFILE ".claude\librarian.log"

function Write-Log($msg) {
    if ($LibrarianLogEnabled) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LibrarianLogFile -Value "[$ts] [write] $msg"
    }
}

$ErrorActionPreference = "Stop"

$inputJson = [Console]::In.ReadToEnd()
Write-Log "Hook fired"

# Extract cwd from JSON
$projectDir = ""
if ($inputJson -match '"cwd"\s*:\s*"([^"]*)"') {
    $projectDir = $Matches[1]
}
if (-not $projectDir) { Write-Log "No cwd found"; exit 0 }
Write-Log "Project: $projectDir"

$memoryLib = Join-Path $projectDir "_memory_library"
if (-not (Test-Path $memoryLib -PathType Container)) { Write-Log "No _memory_library/"; exit 0 }

$scratch = Join-Path $memoryLib ".scratch.md"

# --- Phase 1: Sync auto-memory to scratch ---

$encodedPath = $projectDir.Replace("/", "-").Replace("\", "-").Replace(".", "-")
$autoMemoryDir = Join-Path $env:USERPROFILE ".claude\projects\$encodedPath\memory"

if (Test-Path $autoMemoryDir -PathType Container) {
    Write-Log "Phase 1: Scanning $autoMemoryDir"
    $cutoff = (Get-Date).AddHours(-2)
    $recentFiles = Get-ChildItem -Path $autoMemoryDir -Filter "*.md" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "MEMORY.md" -and $_.LastWriteTime -gt $cutoff }

    foreach ($memFile in $recentFiles) {
        $memName = ""
        $memType = ""
        $body = ""
        $inFrontmatter = $false
        $pastFrontmatter = $false
        $dashes = 0

        foreach ($line in (Get-Content $memFile.FullName)) {
            if ($line -eq "---") {
                $dashes++
                if ($dashes -eq 1) { $inFrontmatter = $true; continue }
                if ($dashes -eq 2) { $inFrontmatter = $false; $pastFrontmatter = $true; continue }
            }
            if ($inFrontmatter) {
                if ($line -match '^name:\s*(.+)') { $memName = $Matches[1] }
                if ($line -match '^type:\s*(.+)') { $memType = $Matches[1] }
            }
            elseif ($pastFrontmatter -and $line.Trim() -and -not $body) {
                $body = $line
            }
        }

        if ($memType -eq "user") { continue }
        if (-not $memName) { continue }

        # Dedup
        $alreadyExists = $false
        if ((Test-Path $scratch) -and (Select-String -Path $scratch -Pattern ([regex]::Escape($memName)) -Quiet -ErrorAction SilentlyContinue)) {
            $alreadyExists = $true
        }
        if (-not $alreadyExists) {
            $allMd = Get-ChildItem -Path $memoryLib -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne ".scratch.md" }
            foreach ($checkFile in $allMd) {
                if (Select-String -Path $checkFile.FullName -Pattern ([regex]::Escape($memName)) -Quiet -ErrorAction SilentlyContinue) {
                    $alreadyExists = $true; break
                }
            }
        }
        if ($alreadyExists) { continue }

        $libraryType = switch ($memType) {
            "feedback"  { "patterns" }
            "project"   { "product" }
            "reference" { "tech" }
            default     { "patterns" }
        }

        Write-Log "Phase 1: Synced '$memName' ($memType -> $libraryType)"
        Add-Content -Path $scratch -Value "## [TAG: global, type: $libraryType]`n- ${memName}: ${body}`n"
    }
}

# --- Phase 2: Process scratch entries ---

if (-not (Test-Path $scratch) -or (Get-Item $scratch).Length -eq 0) { Write-Log "Phase 2: Scratch empty"; exit 0 }

Write-Log "Phase 2: Processing scratch"
$lines = Get-Content $scratch
$today = Get-Date -Format "yyyy-MM-dd"
$unprocessed = @()
$currentPath = $null
$currentType = $null
$currentContent = @()

function Process-Tag {
    param($TagPath, $TagType, $Content)
    if (-not $TagPath -or -not $TagType -or $Content.Count -eq 0) { return }

    $targetDir = if ($TagPath -eq "global") { $memoryLib } else { Join-Path $memoryLib $TagPath }
    $targetFile = Join-Path $targetDir "$TagType.md"

    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    if (-not (Test-Path $targetFile)) {
        Write-Log "Phase 2: Creating $targetFile"
        Set-Content -Path $targetFile -Value "# $TagType"
    }

    $learningCount = ($Content | Where-Object { $_ -match '^\s*-' }).Count
    Write-Log "Phase 2: Routed $learningCount entries -> $targetFile"
    $append = "`n## Session Learnings ($today)`n" + ($Content -join "`n")
    Add-Content -Path $targetFile -Value $append
}

foreach ($line in $lines) {
    if ($line -match '^\#\#\s*\[TAG:\s*') {
        # Process previous tag
        if ($currentPath -and $currentType) {
            Process-Tag -TagPath $currentPath -TagType $currentType -Content $currentContent
        } elseif ($currentPath -and -not $currentType -and $currentContent.Count -gt 0) {
            $unprocessed += "## [TAG: $currentPath]"
            $unprocessed += $currentContent
            $unprocessed += ""
        }

        if ($line -match 'type:\s*([^\]]+)\]') {
            $currentType = $Matches[1].Trim()
            $line -match '\[TAG:\s*([^,]+),' | Out-Null
            $currentPath = $Matches[1].Trim()
        } else {
            $line -match '\[TAG:\s*([^\]]+)\]' | Out-Null
            $currentPath = $Matches[1].Trim()
            $currentType = $null
        }
        $currentContent = @()
    }
    elseif ($currentPath -and $line.Trim()) {
        $currentContent += $line
    }
}

# Process last tag
if ($currentPath -and $currentType) {
    Process-Tag -TagPath $currentPath -TagType $currentType -Content $currentContent
} elseif ($currentPath -and -not $currentType -and $currentContent.Count -gt 0) {
    $unprocessed += "## [TAG: $currentPath]"
    $unprocessed += $currentContent
    $unprocessed += ""
}

if ($unprocessed.Count -gt 0) {
    Set-Content -Path $scratch -Value ($unprocessed -join "`n")
} else {
    Set-Content -Path $scratch -Value ""
}

Write-Log "Done"
exit 0
