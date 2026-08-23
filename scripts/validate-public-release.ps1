[CmdletBinding()]
param(
    [string[]]$AdditionalCandidatePath = @()
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$forbiddenExtensions = '\.(zip|pdf|ppt|pptx|xls|xlsx|bak|tmp)$'
$forbiddenPaths = '(^|/)\.omo(/|$)|^docs/release-manifest\.md$|(^|/)\.ipynb_checkpoints(/|$)'
$windowsAbsolutePath = '(?i)(?:^|[^A-Za-z0-9_])[A-Z]:[\\/](Users|ProgramData|Windows)([\\/]|$)'
$unixAbsolutePath = '(?<![A-Za-z0-9_])/(Users|home|mnt)(/|$)'
$driveMountPattern = '/cont' + 'ent/drive'
$imageUriPattern = 'data:' + 'image/'
$base64PayloadPattern = '[A-Za-z0-9+/]{200,}={0,2}'

$normalizedRoot = ($repositoryRoot.TrimEnd('\', '/') + '\')
$allFiles = Get-ChildItem -LiteralPath $repositoryRoot -File -Recurse | ForEach-Object {
    $fullName = $_.FullName
    if ($fullName.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $fullName.Substring($normalizedRoot.Length).Replace('\', '/')
    }
    else {
        $_.Name
    }
}

$publicCandidates = @($allFiles | Where-Object {
    $_ -notmatch '(^|/)\.git(/|$)' -and
    $_ -notmatch '(^|/)\.omo(/|$)' -and
    $_ -ne 'docs/release-manifest.md'
})

$pathCandidates = @($publicCandidates + $AdditionalCandidatePath)
$pathViolations = @($pathCandidates | Where-Object {
    $_ -match $forbiddenExtensions -or $_ -match $forbiddenPaths
})

$contentFiles = @($publicCandidates | Where-Object { $_ -ne 'scripts/validate-public-release.ps1' })
$contentViolations = New-Object System.Collections.Generic.List[string]
foreach ($relativePath in $contentFiles) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    $content = Get-Content -LiteralPath $fullPath -Raw
    if (
        $content -match $driveMountPattern -or
        $content -match $imageUriPattern -or
        $content -match $windowsAbsolutePath -or
        $content -match $unixAbsolutePath -or
        $content -match $base64PayloadPattern
    ) {
        $contentViolations.Add($relativePath)
    }
}

if ($pathViolations.Count -gt 0 -or $contentViolations.Count -gt 0) {
    if ($pathViolations.Count -gt 0) {
        'REJECTED PATHS:'
        $pathViolations | Sort-Object -Unique
    }
    if ($contentViolations.Count -gt 0) {
        'REJECTED CONTENT FILES:'
        $contentViolations | Sort-Object -Unique
    }
    throw 'Public release validation failed.'
}

"PASS: $($publicCandidates.Count) public candidate file(s) passed path and content checks."
