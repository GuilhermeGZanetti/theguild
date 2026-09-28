# Loads every script/scene headless and prints only errors.
$Root = Split-Path -Parent $PSScriptRoot
$Godot = "C:\Users\ferna\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe"
Set-Location $Root
& $Godot --headless --path . --import 2>&1 | Out-Null
& $Godot --headless --path . -s res://tools/check_scripts.gd 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match "SCRIPT ERROR|Parse Error|Compile Error|FAILED|CANNOT|check_scripts done|at: GDScript" }
