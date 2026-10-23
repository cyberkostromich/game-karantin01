#!/usr/bin/env bash
# Сборка релизов: Linux x86_64 и Windows x86_64 (PCK встроен в исполняемый файл) + zip в export/.
# Нужны шаблоны экспорта Godot 4.6 в ~/.local/share/godot/export_templates/4.6.stable/.
set -euo pipefail
cd "$(dirname "$0")/../.."
VER=$(grep -oP 'config/version="\K[^"]+' project.godot)
godot --headless --import >/dev/null 2>&1 || true
mkdir -p export/linux export/windows
godot --headless --export-release "Linux" export/linux/karantin_moskva.x86_64
godot --headless --export-release "Windows" export/windows/karantin_moskva.exe
(cd export/linux && zip -q -9 "../karantin_moskva_${VER}_linux_x86_64.zip" karantin_moskva.x86_64)
(cd export/windows && zip -q -9 "../karantin_moskva_${VER}_windows_x86_64.zip" karantin_moskva.exe)
ls -la export/*.zip
