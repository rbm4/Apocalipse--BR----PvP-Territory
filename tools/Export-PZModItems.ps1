param(
    [Parameter(Position = 0)]
    [string[]] $Root = @("."),

    [ValidateSet("LuaArray", "Text", "Json", "Csv")]
    [string] $Format = "LuaArray",

    [ValidateSet("Global", "PerMod")]
    [string] $DuplicateScope = "Global",

    [string] $OutFile,

    [switch] $IncludeVanilla,

    [switch] $SummaryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ExistingRoot {
    param([string] $Path)

    try {
        $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
        foreach ($entry in $resolved) {
            if (Test-Path -LiteralPath $entry.Path -PathType Container) {
                $entry.Path
            }
        }
    } catch {
        Write-Warning "Skipping missing root: $Path"
    }
}

function Read-ModInfo {
    param([string] $ScriptPath, [string[]] $ScanRoots)

    function Convert-ModInfoFileToObject {
        param([string] $ModInfoPath)

        $modDirectory = Split-Path -Parent $ModInfoPath
        $info = @{
            id = $null
            name = $null
            path = $modDirectory
        }

        foreach ($line in Get-Content -LiteralPath $ModInfoPath) {
            if ($line -match '^\s*id\s*=\s*(.+?)\s*$') {
                $info.id = $Matches[1].Trim()
            } elseif ($line -match '^\s*name\s*=\s*(.+?)\s*$') {
                $info.name = $Matches[1].Trim()
            }
        }

        if ([string]::IsNullOrWhiteSpace($info.name)) {
            $info.name = Split-Path -Leaf $modDirectory
        }
        if ([string]::IsNullOrWhiteSpace($info.id)) {
            $info.id = Split-Path -Leaf $modDirectory
        }

        [pscustomobject] $info
    }

    $directory = Get-Item -LiteralPath (Split-Path -Parent $ScriptPath)
    $rootSet = @{}
    foreach ($root in $ScanRoots) {
        $rootSet[(Get-Item -LiteralPath $root).FullName.TrimEnd('\')] = $true
    }

    while ($null -ne $directory) {
        $modInfoPath = Join-Path $directory.FullName "mod.info"
        if (Test-Path -LiteralPath $modInfoPath -PathType Leaf) {
            return Convert-ModInfoFileToObject $modInfoPath
        }

        if ($null -ne $directory.Parent -and $directory.Parent.Name -eq "mods") {
            $versionedModInfo = Get-ChildItem -LiteralPath $directory.FullName -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object {
                    $candidate = Join-Path $_.FullName "mod.info"
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $candidate
                    }
                } |
                Select-Object -First 1

            if ($versionedModInfo) {
                $info = Convert-ModInfoFileToObject $versionedModInfo
                $info.path = $directory.FullName
                return $info
            }

            return [pscustomobject] @{
                id = $directory.Name
                name = $directory.Name
                path = $directory.FullName
            }
        }

        $current = $directory.FullName.TrimEnd('\')
        if ($rootSet.ContainsKey($current)) {
            break
        }

        $directory = $directory.Parent
    }

    $fallback = Split-Path -Leaf (Split-Path -Parent $ScriptPath)
    [pscustomobject] @{
        id = $fallback
        name = $fallback
        path = Split-Path -Parent $ScriptPath
    }
}

function Remove-ScriptComments {
    param([string] $Text)

    $withoutBlockComments = [regex]::Replace($Text, '/\*.*?\*/', '', 'Singleline')
    [regex]::Replace($withoutBlockComments, '(?m)//.*$', '')
}

function Get-ScriptItems {
    param([string] $Path)

    $text = Get-Content -LiteralPath $Path -Raw
    $text = Remove-ScriptComments $text
    $moduleStack = New-Object System.Collections.Generic.List[object]
    $currentModule = $null
    $pendingModule = $null
    $braceDepth = 0
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($line in ($text -split "`r?`n")) {
        while ($moduleStack.Count -gt 0 -and $braceDepth -le $moduleStack[$moduleStack.Count - 1].EndDepth) {
            $moduleStack.RemoveAt($moduleStack.Count - 1)
            if ($moduleStack.Count -gt 0) {
                $currentModule = $moduleStack[$moduleStack.Count - 1].Name
            } else {
                $currentModule = $null
            }
        }

        if ($line -match '^\s*module\s+([A-Za-z0-9_.-]+)\s*\{') {
            $moduleStack.Add([pscustomobject] @{
                Name = $Matches[1]
                EndDepth = $braceDepth
            })
            $currentModule = $Matches[1]
            $pendingModule = $null
        } elseif ($line -match '^\s*module\s+([A-Za-z0-9_.-]+)\s*$') {
            $pendingModule = $Matches[1]
        } elseif ($null -ne $pendingModule -and $line -match '^\s*\{') {
            $moduleStack.Add([pscustomobject] @{
                Name = $pendingModule
                EndDepth = $braceDepth
            })
            $currentModule = $pendingModule
            $pendingModule = $null
        }

        if ($null -ne $currentModule -and $line -match '^\s*item\s+([A-Za-z0-9_.-]+)(?:\s*:\s*[A-Za-z0-9_.-]+)?\s*(?:\{|$)') {
            $itemName = $Matches[1]
            $items.Add([pscustomobject] @{
                Module = $currentModule
                Item = $itemName
                FullName = "$currentModule.$itemName"
                File = $Path
            })
        }

        $openCount = ([regex]::Matches($line, '\{')).Count
        $closeCount = ([regex]::Matches($line, '\}')).Count
        $braceDepth += $openCount - $closeCount
    }

    $items
}

function Convert-ToLuaName {
    param([string] $Value)
    $name = [regex]::Replace($Value, '[^A-Za-z0-9_]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($name)) {
        return "mod_loot"
    }
    if ($name -match '^[0-9]') {
        return "mod_$name"
    }
    $name
}

function Format-LuaArray {
    param([string[]] $Items)

    if ($Items.Count -eq 0) {
        return "{}"
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lineItems = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Items) {
        $lineItems.Add("`"$item`"")
        if ($lineItems.Count -eq 4) {
            $lines.Add("    " + ($lineItems -join ", "))
            $lineItems.Clear()
        }
    }
    if ($lineItems.Count -gt 0) {
        $lines.Add("    " + ($lineItems -join ", "))
    }

    "{`n" + ($lines -join ",`n") + "`n}"
}

$scanRoots = @(@($Root | ForEach-Object { Resolve-ExistingRoot $_ }) | Select-Object -Unique)
if ($scanRoots.Count -eq 0) {
    throw "No valid roots to scan."
}

$scriptFiles = foreach ($scanRoot in $scanRoots) {
    Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Filter "*.txt" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\media\\scripts\\' }
}

$rows = New-Object System.Collections.Generic.List[object]
$seenGlobal = @{}
$seenPerMod = @{}

foreach ($file in $scriptFiles) {
    $modInfo = Read-ModInfo -ScriptPath $file.FullName -ScanRoots $scanRoots
    if (-not $IncludeVanilla -and $modInfo.id -eq "Base") {
        continue
    }

    foreach ($item in Get-ScriptItems -Path $file.FullName) {
        $dedupeKey = if ($DuplicateScope -eq "Global") {
            $item.FullName.ToLowerInvariant()
        } else {
            ($modInfo.id + "|" + $item.FullName).ToLowerInvariant()
        }

        if ($seenGlobal.ContainsKey($dedupeKey) -or $seenPerMod.ContainsKey($dedupeKey)) {
            continue
        }

        if ($DuplicateScope -eq "Global") {
            $seenGlobal[$dedupeKey] = $true
        } else {
            $seenPerMod[$dedupeKey] = $true
        }

        $rows.Add([pscustomobject] @{
            ModName = $modInfo.name
            ModId = $modInfo.id
            ModPath = $modInfo.path
            Module = $item.Module
            Item = $item.Item
            FullName = $item.FullName
            File = $item.File
        })
    }
}

$rows = @($rows | Sort-Object ModName, Module, Item)

if ($SummaryOnly) {
    $output = $rows |
        Group-Object ModName |
        Sort-Object Name |
        ForEach-Object { "{0}: {1} items" -f $_.Name, $_.Count }
} elseif ($Format -eq "Json") {
    $output = $rows | ConvertTo-Json -Depth 4
} elseif ($Format -eq "Csv") {
    $output = $rows | ConvertTo-Csv -NoTypeInformation
} elseif ($Format -eq "Text") {
    $output = $rows | ForEach-Object { "{0} | {1}" -f $_.ModName, $_.FullName }
} else {
    $chunks = New-Object System.Collections.Generic.List[string]
    foreach ($group in ($rows | Group-Object ModName | Sort-Object Name)) {
        $first = $group.Group | Select-Object -First 1
        $varName = Convert-ToLuaName "$($first.ModId)_loot"
        $items = @($group.Group | ForEach-Object { $_.FullName })
        $chunks.Add("-- $($first.ModName) [$($first.ModId)]")
        $chunks.Add("local $varName = " + (Format-LuaArray $items))
    }
    $output = $chunks -join "`n`n"
}

if ($OutFile) {
    $parent = Split-Path -Parent $OutFile
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    $output | Set-Content -LiteralPath $OutFile -Encoding UTF8
    Write-Host "Wrote $($rows.Count) item ids to $OutFile"
} else {
    $output
}
