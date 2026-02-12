#!/usr/bin/env bash
set -euo pipefail

echo "[core] installing TigerVNC + XFCE..."
sudo apt-get update
sudo apt-get install -y tigervnc-standalone-server tigervnc-common xfce4 xfce4-goodies dbus-x11

echo "[core] done"
