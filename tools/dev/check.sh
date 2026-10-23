#!/bin/sh
# Быстрая проверка компиляции всех скриптов: грузим каждый .gd и печатаем ошибки.
cd "$(dirname "$0")/../.."
timeout 300 godot --headless --import >/dev/null 2>&1
timeout 120 godot --headless -s tools/dev/compile_all.gd 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|ERROR:|at: GDScript|COMPILED" | grep -v "I18n" | head -${1:-40}
