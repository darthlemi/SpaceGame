@echo off
set "GODOT=%GODOT_EXE%"
if not defined GODOT set "GODOT=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
cd /d "%~dp0.."
"%GODOT%" --path . res://scenes/editor/map_editor.tscn
