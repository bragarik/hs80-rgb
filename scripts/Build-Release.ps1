# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$')]
    [string]$Version,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

$notes = Join-Path $root ('releases/{0}.md' -f $Version)
if (-not (Test-Path -LiteralPath $notes -PathType Leaf)) {
    throw "Release notes not found: $notes"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$staging = Join-Path ([IO.Path]::GetTempPath()) ('hs80-release-' + [Guid]::NewGuid().ToString('N'))
$packageDir = Join-Path $staging 'hs80-rgb'
$zipName = 'hs80-rgb-{0}.zip' -f $Version
$zipPath = Join-Path $OutputDirectory $zipName

try {
    New-Item -ItemType Directory -Path (Join-Path $packageDir 'tests') -Force | Out-Null
    foreach ($file in @('hs80-rgb.bat', 'hs80-rgb.ps1', 'README.md', 'LICENSE', 'tests/Smoke.Tests.ps1', 'tests/Lifecycle.Tests.ps1', 'tests/Startup.Tests.ps1')) {
        $source = Join-Path $root $file
        $target = Join-Path $packageDir $file
        if ($file -match '\.(bat|ps1)$') {
            # UTF-8 without BOM, CRLF. Scripts contain ASCII for PS 5.1 compatibility.
            $content = [IO.File]::ReadAllText($source) -replace '\r?\n', "`r`n"
            [IO.File]::WriteAllText($target, $content, (New-Object Text.UTF8Encoding($false)))
        } else {
            Copy-Item -LiteralPath $source -Destination $target
        }
    }
    Copy-Item -LiteralPath $notes -Destination (Join-Path $packageDir 'RELEASE-NOTES.md')
    Compress-Archive -LiteralPath $packageDir -DestinationPath $zipPath -Force
    $checksum = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumPath = $zipPath + '.sha256'
    [IO.File]::WriteAllText($checksumPath, "$checksum  $zipName`n", (New-Object Text.UTF8Encoding($false)))

    [pscustomobject]@{
        Version = $Version
        ZipPath = $zipPath
        ChecksumPath = $checksumPath
        NotesPath = $notes
    }
} finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
