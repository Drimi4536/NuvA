#!/usr/bin/env bash
# Проверка проекта: сборка скриптов и все тесты. --shots — ещё снимки экранов в out/shots (нужен xvfb).
set -e
cd "$(dirname "$0")/.."
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . res://tools/parse_all.tscn 2>&1 | grep -E "PARSE|SCRIPT ERROR|не собирается"
if command -v xvfb-run >/dev/null; then
  xvfb-run -a godot --path . --resolution 1180x780 res://tests/test_all.tscn 2>&1 | grep -E "FAIL|TEST|SCRIPT ERROR"
else
  godot --headless --path . res://tests/test_all.tscn 2>&1 | grep -E "FAIL|TEST|SCRIPT ERROR"
fi
if [ "$1" == "--shots" ]; then
  OUT=out/shots xvfb-run -a godot --path . --resolution 1180x780 res://tools/shots.tscn 2>&1 | grep -E "SHOTS|SCRIPT ERROR"
fi
