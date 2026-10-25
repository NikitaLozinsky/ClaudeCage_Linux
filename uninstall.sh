#!/usr/bin/env bash
# ==============================================================================
# ClaudeCage Uninstaller
# Cleans up sandbox, firewall rules, binaries and wrappers
# ==============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${BOLD}${RED}━━━ Удаление ClaudeCage ━━━${NC}"

# Остановка и сброс netns
if command -v claude-vpn &>/dev/null; then
    sudo /usr/local/bin/claude-vpn --down 2>/dev/null || true
fi

# Отключение systemd
if systemctl is-active --quiet claude-vpn.service 2>/dev/null; then
    sudo systemctl stop claude-vpn.service 2>/dev/null || true
    sudo systemctl disable claude-vpn.service 2>/dev/null || true
fi
sudo rm -f /etc/systemd/system/claude-vpn.service
sudo systemctl daemon-reload 2>/dev/null || true

# Удаление системных файлов
sudo rm -f /usr/local/bin/claude-vpn
sudo rm -rf /usr/local/lib/claude-vpn
sudo rm -f /etc/sudoers.d/claude-vpn
echo -e "${GREEN}[✓]${NC} Системные файлы и sudoers удалены."

# Восстановление claude-raw если был
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
USER_BIN="${TARGET_HOME}/.local/bin"

if [[ -f "${USER_BIN}/claude-raw" ]]; then
    mv -f "${USER_BIN}/claude-raw" "${USER_BIN}/claude"
    echo -e "${GREEN}[✓]${NC} Восстановлен оригинальный бинарник claude"
else
    rm -f "${USER_BIN}/claude"
fi

rm -f "${USER_BIN}/claude-desktop"
rm -f "${USER_BIN}/celltest"
rm -f "${USER_BIN}/claude-vpn"
rm -f "${TARGET_HOME}/.config/fish/functions/claude.fish"
rm -f "${TARGET_HOME}/.config/fish/functions/claude-desktop.fish"

echo -e "${GREEN}${BOLD}ClaudeCage успешно удалён.${NC}"
