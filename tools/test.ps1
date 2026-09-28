# Imports the project (registers class_names) and runs the GUT suite headless.
#   powershell -ExecutionPolicy Bypass -File tools/test.ps1 [-Dir res://tests/unit] [-Test res://tests/unit/test_x.gd]
param([string]$Dir = "res://tests/unit", [string]$Test = "", [switch]$Full)
$Root = Split-Path -Parent $PSScriptRoot
$Godot = "C:\Users\ferna\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe"
Set-Location $Root
& $Godot --headless --path . --import 2>&1 | Out-Null
$gutArgs = @("--headless", "--path", ".", "-s", "addons/gut/gut_cmdln.gd", "-gexit")
if ($Test -ne "") { $gutArgs += "-gtest=$Test" } else { $gutArgs += "-gdir=$Dir" }
$out = & $Godot @gutArgs 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch "\[\s*\d+% \]" }
if ($Full) { $out } else { $out | Select-String -Pattern "SCRIPT ERROR|Parse Error|\[Failed\]|passed|Passing|Failing|autopilot|AI vs AI|at line|Invalid|^\s+w\d|facilities|ERROR: [^5]" }
