[CmdletBinding()]
param(
    [string[]]$AdditionalCandidatePath = @(),
    [string[]]$AdditionalCandidateContent = @(),
    [string[]]$AdditionalNotebookJson = @()
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$forbiddenExtensions = '\.(csv|tsv|parquet|feather|h5|hdf5|npy|npz|pkl|pickle|joblib|sav|model|zip|tar|gz|bz2|7z|rar|pdf|ppt|pptx|pps|ppsx|xls|xlsx|xlsm|doc|docx|odt|rtf|hwp|bak|tmp)$'
$forbiddenPaths = '(^|/)\.omo(/|$)|^docs/release-manifest\.md$|(^|/)\.ipynb_checkpoints(/|$)'
$forbiddenDataPath = '^data/(?!README\.md$)'
$windowsAbsolutePath = '(?i)(?:^|[^A-Za-z0-9_])[A-Z]:[\\/]'
$windowsAbsoluteCandidatePath = '(?i)^[A-Z]:[\\/]'
$unixAbsolutePath = '(?<![A-Za-z0-9_])/(Users|home|mnt)(/|$)'
$driveMountPattern = '/cont' + 'ent/drive'
$imageUriPattern = 'data:' + 'image/'
$base64PayloadPattern = '[A-Za-z0-9+/]{200,}={0,2}'

function Add-StringLeaves {
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Node,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Destination
    )

    if ($null -eq $Node) { return }
    if ($Node -is [string]) {
        $Destination.Add($Node)
        return
    }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [pscustomobject]) {
        foreach ($item in $Node) { Add-StringLeaves -Node $item -Destination $Destination }
        return
    }
    if ($Node -is [pscustomobject]) {
        foreach ($property in $Node.PSObject.Properties) {
            Add-StringLeaves -Node $property.Value -Destination $Destination
        }
    }
}

function Find-UnsafeMetadataKeys {
    param(
        [Parameter(Mandatory = $true)]$Node,
        [string]$Prefix = 'metadata'
    )

    $findings = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Node) { return $findings }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [pscustomobject] -and $Node -isnot [string]) {
        $index = 0
        foreach ($item in $Node) {
            foreach ($finding in (Find-UnsafeMetadataKeys -Node $item -Prefix "$Prefix[$index]")) { $findings.Add($finding) }
            $index++
        }
        return $findings
    }
    if ($Node -is [pscustomobject]) {
        foreach ($property in $Node.PSObject.Properties) {
            $path = "$Prefix.$($property.Name)"
            if ($property.Name -match '(?i)^(colab|authors?|authorship(_tag)?|displayname|userid|email)$') {
                $findings.Add($path)
            }
            foreach ($finding in (Find-UnsafeMetadataKeys -Node $property.Value -Prefix $path)) { $findings.Add($finding) }
        }
    }
    return $findings
}

function Test-PublicNotebook {
    param(
        [Parameter(Mandatory = $true)][string]$NotebookJson,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $violations = New-Object System.Collections.Generic.List[string]
    try { $notebook = $NotebookJson | ConvertFrom-Json -ErrorAction Stop }
    catch {
        $violations.Add("${Label}: invalid JSON")
        return $violations
    }

    if ($notebook.nbformat -ne 4 -or $null -eq $notebook.cells) {
        $violations.Add("${Label}: invalid notebook structure")
        return $violations
    }

    $cellIndex = 0
    foreach ($cell in @($notebook.cells)) {
        if ($cell.PSObject.Properties.Name -contains 'execution_count' -and $null -ne $cell.execution_count) {
            $violations.Add("${Label}: non-null execution_count at cell $cellIndex")
        }
        if ($cell.PSObject.Properties.Name -contains 'outputs' -and @($cell.outputs).Count -gt 0) {
            $violations.Add("${Label}: non-empty outputs at cell $cellIndex")
        }
        foreach ($unsafeKey in (Find-UnsafeMetadataKeys -Node $cell.metadata -Prefix "cells[$cellIndex].metadata")) {
            $violations.Add("${Label}: unsafe metadata key $unsafeKey")
        }
        $cellIndex++
    }
    foreach ($unsafeKey in (Find-UnsafeMetadataKeys -Node $notebook.metadata -Prefix 'metadata')) {
        $violations.Add("${Label}: unsafe metadata key $unsafeKey")
    }

    $stringLeaves = New-Object System.Collections.Generic.List[string]
    Add-StringLeaves -Node $notebook -Destination $stringLeaves
    foreach ($value in $stringLeaves) {
        if ($value -match $driveMountPattern -or $value -match $imageUriPattern -or
            $value -match $windowsAbsolutePath -or $value -match $unixAbsolutePath -or
            $value -match $base64PayloadPattern) {
            $violations.Add("${Label}: forbidden notebook content")
            break
        }
    }
    return $violations
}

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
    $_ -match $forbiddenExtensions -or $_ -match $forbiddenPaths -or
    $_ -match $forbiddenDataPath -or $_ -match $windowsAbsoluteCandidatePath
})

$contentFiles = @($publicCandidates | Where-Object {
    $_ -ne 'scripts/validate-public-release.ps1' -and $_ -notmatch '\.ipynb$'
})
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

$additionalContentIndex = 0
foreach ($content in $AdditionalCandidateContent) {
    if ($content -match $driveMountPattern -or $content -match $imageUriPattern -or
        $content -match $windowsAbsolutePath -or $content -match $unixAbsolutePath -or
        $content -match $base64PayloadPattern) {
        $contentViolations.Add("<additional-content:$additionalContentIndex>")
    }
    $additionalContentIndex++
}

$notebookViolations = New-Object System.Collections.Generic.List[string]
foreach ($relativePath in @($publicCandidates | Where-Object { $_ -match '\.ipynb$' })) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    foreach ($violation in (Test-PublicNotebook -NotebookJson (Get-Content -LiteralPath $fullPath -Raw) -Label $relativePath)) {
        $notebookViolations.Add($violation)
    }
}
$additionalNotebookIndex = 0
foreach ($notebookJson in $AdditionalNotebookJson) {
    foreach ($violation in (Test-PublicNotebook -NotebookJson $notebookJson -Label "<additional-notebook:$additionalNotebookIndex>")) {
        $notebookViolations.Add($violation)
    }
    $additionalNotebookIndex++
}

if ($pathViolations.Count -gt 0 -or $contentViolations.Count -gt 0 -or $notebookViolations.Count -gt 0) {
    if ($pathViolations.Count -gt 0) {
        'REJECTED PATHS:'
        $pathViolations | Sort-Object -Unique
    }
    if ($contentViolations.Count -gt 0) {
        'REJECTED CONTENT FILES:'
        $contentViolations | Sort-Object -Unique
    }
    if ($notebookViolations.Count -gt 0) {
        'REJECTED NOTEBOOKS:'
        $notebookViolations | Sort-Object -Unique
    }
    throw 'Public release validation failed.'
}

"PASS: $($publicCandidates.Count) public candidate file(s) passed path, content, and notebook checks."
