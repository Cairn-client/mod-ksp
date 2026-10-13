# Copyright (C) 2026 the Cairn contributors. SPDX-License-Identifier: MIT (as the project it is part of)
<#
.SYNOPSIS
    Builds the Cairn mod pack for Kerbal Space Program (Luna Multiplayer): release\Cairn-Pack-ksp-<version>.zip and
    release\pack-index.json (what the Cairn launcher reads to see a newer pack exists).

.DESCRIPTION
    An *external* pack that goes into the game's own folder (docs in the launcher repository: docs/PACKS.md, installDir ".").
    The client of Luna Multiplayer is built against KSP's own assemblies, which this project keeps in a password-protected archive that
    only its maintainers' build service can open, so the pack is made from the client zip the project itself publishes on its releases
    (LunaMultiplayer-Client-Release.zip: GameData\LunaMultiplayer and the Harmony loader it needs in GameData\000_Harmony). The release
    workflow checks that zip against a pinned sha256, so a changed upstream file is never packed unseen.

      mod\GameData\...   the client zip's GameData folder, as it is
      pack.json          the contract with the launcher
      manifest.txt       MOD|<path>|<size>|<sha256>, one line per file

    The pack's version is the VERSION file (strict X.Y.Z, this project's own); Luna Multiplayer's version is the pack's "upstream".
    A file of the game's with the same name and other bytes is never overwritten by the launcher, so a Harmony the player already has
    (many mods bring one) is reported, not replaced.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ClientZip,
    [Parameter(Mandatory)][string] $UpstreamVersion
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$version = (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim()
if ($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw "VERSION must be strict X.Y.Z, got '$version'" }
if ($UpstreamVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw "upstream version must be X.Y.Z, got '$UpstreamVersion'" }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$release = Join-Path $root 'release'
$stage = Join-Path $release 'pack-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$mod = Join-Path $stage 'mod'
New-Item -ItemType Directory -Force -Path $mod | Out-Null

$destFull = [IO.Path]::GetFullPath($mod).TrimEnd('\') + '\'
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $ClientZip))
try {
    foreach ($e in $zip.Entries) {
        $name = $e.FullName.Replace('\', '/')
        if ($name.EndsWith('/') -or -not $name.StartsWith('GameData/')) { continue }
        $target = [IO.Path]::GetFullPath((Join-Path $mod ($name -replace '/', '\')))
        if (-not $target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) { throw "the archive has a path outside its folder: $($e.FullName)" }
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
    }
} finally { $zip.Dispose() }
foreach ($n in @('GameData\LunaMultiplayer\Plugins\LmpClient.dll', 'GameData\000_Harmony\0Harmony.dll', 'GameData\LunaMultiplayer\LunaMultiplayer.version')) {
    if (-not (Test-Path (Join-Path $mod $n))) { throw "the pack is missing $n" }
}

function Get-Sha256([string] $Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$launcherMin = '0.3.22'
$packJson = [ordered]@{
    schema      = 2
    id          = 'ksp'
    game        = 'ksp'
    version     = $version
    upstream    = $UpstreamVersion
    kind        = 'external'
    installDir  = '.'
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $stage 'pack.json'), (($packJson | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$lines = New-Object System.Collections.Generic.List[string]
foreach ($f in Get-ChildItem $mod -Recurse -File | Sort-Object FullName) {
    $rel = $f.FullName.Substring($mod.Length + 1)
    $lines.Add(('MOD|{0}|{1}|{2}' -f $rel, $f.Length, (Get-Sha256 $f.FullName)))
}
[IO.File]::WriteAllText((Join-Path $stage 'manifest.txt'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$zipName = "Cairn-Pack-ksp-$version.zip"
$zipPath = Join-Path $release $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$fs = [IO.File]::Open($zipPath, 'Create')
try {
    $z = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $stage -Recurse -File) {
            $rel = $f.FullName.Substring($stage.Length + 1) -replace '\\', '/'
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $z.Dispose() }
} finally { $fs.Dispose() }

$index = [ordered]@{
    schema      = 2
    id          = 'ksp'
    game        = 'ksp'
    version     = $version
    upstream    = $UpstreamVersion
    kind        = 'external'
    file        = $zipName
    sha256      = Get-Sha256 $zipPath
    size        = (Get-Item $zipPath).Length
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $release 'pack-index.json'), (($index | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "pack: $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB), version $version, Luna Multiplayer $UpstreamVersion, $($lines.Count) files"
