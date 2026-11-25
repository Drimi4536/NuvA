#!/usr/bin/env bash
# Piper для Linux (тесты и снимки в контейнере): кладёт voice/piper-linux (в git не входит).
# Словари espeak — те же урезанные, что и у Windows-версии (только английский).
set -e
cd "$(dirname "$0")/.."
[ -x voice/piper-linux/piper ] && exit 0
tmp=$(mktemp -d)
curl -sSL -o "$tmp/p.tgz" https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz
tar xzf "$tmp/p.tgz" -C "$tmp"
rm -rf voice/piper-linux
mv "$tmp/piper" voice/piper-linux
rm -rf voice/piper-linux/espeak-ng-data
cp -r voice/piper/espeak-ng-data voice/piper-linux/espeak-ng-data
rm -rf "$tmp"
echo "piper-linux ok"
