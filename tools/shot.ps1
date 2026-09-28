# Renders a developer screenshot: tools/shot.ps1 <name>  -> tools/_cache/shots/<name>.png
param([string]$Name = "scene_battle", [string]$Res = "1280x720", [int]$Timeout = 150)
$Root = Split-Path -Parent $PSScriptRoot
$Godot = "C:\Users\ferna\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe"
Set-Location $Root
$p = Start-Process -FilePath $Godot -ArgumentList @("--path", ".", "--resolution", $Res, "--", "--shot=$Name") -NoNewWindow -PassThru -RedirectStandardError tools/_cache/err.txt -RedirectStandardOutput tools/_cache/out.txt
$p | Wait-Process -Timeout $Timeout -ErrorAction SilentlyContinue
if (!$p.HasExited) { $p | Stop-Process -Force; "TIMEOUT" }
Get-Content tools/_cache/err.txt, tools/_cache/out.txt | Where-Object { $_ -match "ERROR|SCRIPT|at: |DBG|FLOW|INPUT" -and $_ -notmatch "icon.png|resources still|ObjectDB" } | Select-Object -First 40
