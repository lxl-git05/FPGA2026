[CmdletBinding()]
param(
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootPath = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$projectNamePattern = '^[0-9]{2}-'

function Get-DirectoryInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $files = @(Get-ChildItem -LiteralPath $LiteralPath -Recurse -File -Force -ErrorAction Stop)
    $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sizeBytes) {
        $sizeBytes = 0
    }

    [pscustomobject]@{
        FileCount = $files.Count
        SizeBytes = [long]$sizeBytes
    }
}

function Format-FileSize {
    param(
        [Parameter(Mandatory = $true)]
        [long]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return ('{0:N2} GB' -f ($Bytes / 1GB))
    }
    if ($Bytes -ge 1MB) {
        return ('{0:N2} MB' -f ($Bytes / 1MB))
    }
    if ($Bytes -ge 1KB) {
        return ('{0:N2} KB' -f ($Bytes / 1KB))
    }
    return ('{0} B' -f $Bytes)
}

$targets = @()
$projectDirectories = @(
    Get-ChildItem -LiteralPath $rootPath -Directory -Force |
        Where-Object { $_.Name -match $projectNamePattern }
)

foreach ($projectDirectory in $projectDirectories) {
    $projectFiles = @(Get-ChildItem -LiteralPath $projectDirectory.FullName -File -Filter '*.xpr')

    foreach ($projectFile in $projectFiles) {
        $simPath = Join-Path $projectDirectory.FullName ($projectFile.BaseName + '.sim')
        if (-not (Test-Path -LiteralPath $simPath -PathType Container)) {
            continue
        }

        $simItem = Get-Item -LiteralPath $simPath -Force
        $simFullPath = [System.IO.Path]::GetFullPath($simItem.FullName)
        $expectedParent = [System.IO.Path]::GetFullPath($projectDirectory.FullName).TrimEnd('\')
        $actualParent = [System.IO.Path]::GetDirectoryName($simFullPath).TrimEnd('\')
        $expectedName = $projectFile.BaseName + '.sim'

        if (-not $simFullPath.StartsWith($rootPath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing path outside the script directory: $simFullPath"
        }
        if (-not $actualParent.Equals($expectedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The simulation directory is not beside its project file: $simFullPath"
        }
        if (-not $simItem.Name.Equals($expectedName, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The simulation directory does not match its project name: $simFullPath"
        }
        if (($simItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing a linked simulation directory: $simFullPath"
        }

        $directoryInfo = Get-DirectoryInfo -LiteralPath $simFullPath
        $targets += [pscustomobject]@{
            Project   = $projectDirectory.Name
            Directory = $simItem.Name
            FileCount = $directoryInfo.FileCount
            SizeBytes = $directoryInfo.SizeBytes
            FullPath  = $simFullPath
        }
    }
}

$targets = @($targets | Sort-Object FullPath -Unique)

if ($targets.Count -eq 0) {
    Write-Host 'No Vivado .sim directories were found.'
    exit 0
}

$totalBytes = [long](($targets | Measure-Object -Property SizeBytes -Sum).Sum)
$targets |
    Select-Object Project, Directory, FileCount, @{Name = 'Size'; Expression = { Format-FileSize $_.SizeBytes } }, FullPath |
    Format-Table -AutoSize

Write-Host ("Found {0} simulation directories. Estimated space: {1}." -f $targets.Count, (Format-FileSize $totalBytes))

if (-not $Apply) {
    Write-Host 'Preview mode: no files were deleted. Run with -Apply to clean:'
    Write-Host '  .\clean_vivado_sim.ps1 -Apply'
    exit 0
}

$runningTools = @(
    Get-Process -Name 'vivado', 'xsim', 'xelab', 'xvlog' -ErrorAction SilentlyContinue
)
if ($runningTools.Count -gt 0) {
    $processNames = ($runningTools | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
    throw "Vivado simulation tools are running ($processNames). Close them before cleanup."
}

$deletedCount = 0
$deletedBytes = 0L
$failedTargets = @()

foreach ($target in $targets) {
    try {
        Remove-Item -LiteralPath $target.FullPath -Recurse -Force -ErrorAction Stop
        $deletedCount++
        $deletedBytes += $target.SizeBytes
        Write-Host ("Deleted: {0}" -f $target.FullPath)
    }
    catch {
        $failedTargets += $target.FullPath
        Write-Error ("Failed to delete: {0}`n{1}" -f $target.FullPath, $_.Exception.Message)
    }
}

Write-Host ("Cleanup complete. Deleted: {0}; failed: {1}; freed about: {2}." -f $deletedCount, $failedTargets.Count, (Format-FileSize $deletedBytes))

if ($failedTargets.Count -gt 0) {
    exit 1
}
