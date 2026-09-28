# Regenerates every generated asset of A Guilda.
#   powershell -ExecutionPolicy Bypass -File tools/build_assets.ps1 [-Only units,props,textures,ui,audio]
param([string]$Only = "units,props,textures,ui,audio")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Blender = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
$Py = Join-Path $Root ".venv\Scripts\python.exe"
Set-Location $Root
$steps = $Only.Split(",")

function Run-Py($script, $argsList) {
    # Blender's bundled Python prints a harmless sitecustomize warning on stderr.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $Py $script @argsList 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch "sitecustomize|FileNotFoundError: \[WinError 2\]|NativeCommandError|CategoryInfo|FullyQualifiedErrorId|^\s*\+|^At |caractere" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "$script failed ($code)" }
}

if ($steps -contains "units") {
    Write-Host "== units: rendering in Blender (4 shards)"
    $jobs = @()
    for ($i = 0; $i -lt 4; $i++) {
        $jobs += Start-Process -FilePath $Blender -ArgumentList @("-b", "--factory-startup", "--python", "tools/blender/units.py", "--", "--out", "tools/_cache/units", "--shard", "$i/4") -NoNewWindow -PassThru -RedirectStandardOutput "tools/_cache/units_$i.log"
    }
    $jobs | Wait-Process
    Write-Host "== units: post-processing"
    Run-Py "tools/py/sprites_post.py" @()
}
if ($steps -contains "props") {
    Write-Host "== props: modelling in Blender"
    & $Blender -b --factory-startup --python tools/blender/props.py -- --out assets/models/props 2>&1 | Select-String "\[props\]|Error|Traceback"
}
if ($steps -contains "textures") {
    Write-Host "== textures"
    Run-Py "tools/py/textures.py" @()
}
if ($steps -contains "ui") {
    Write-Host "== ui"
    Run-Py "tools/py/ui_art.py" @()
}
if ($steps -contains "audio") {
    Write-Host "== audio"
    Run-Py "tools/py/audio.py" @()
}
Write-Host "done"
