#!/usr/bin/env bash
# ==============================================================================
# ClaudeCage Uninstaller
# Cleans up sandbox, firewall rules, binaries, systemd units and wrappers
# ==============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${BOLD}${RED}━━━ Удаление ClaudeCage ━━━${NC}"

# 1. Остановка и сброс netns
if command -v claude-vpn &>/dev/null; then
    sudo /usr/local/bin/claude-vpn --down 2>/dev/null || true
fi

# 2. Отключение и удаление systemd служб
for unit in claude-vpn-watchdog.service claude-vpn.service; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        sudo systemctl stop "$unit" 2>/dev/null || true
    fi
    sudo systemctl disable "$unit" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$unit"
done
sudo systemctl daemon-reload 2>/dev/null || true
echo -e "${GREEN}[✓]${NC} Службы systemd остановлены и удалены."

# 3. Удаление системных файлов и sudoers
sudo rm -f /usr/local/bin/claude-vpn
sudo rm -f /usr/local/bin/celltest
sudo rm -rf /usr/local/lib/claude-vpn
sudo rm -f /etc/sudoers.d/claude-vpn
echo -e "${GREEN}[✓]${NC} Системные бинарники, библиотеки и sudoers удалены."

# 4. Восстановление пользовательского бинарника claude
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
[[ -z "$TARGET_HOME" ]] && TARGET_HOME="/home/${TARGET_USER}"
USER_BIN="${TARGET_HOME}/.local/bin"

if [[ -f "${USER_BIN}/claude-raw" ]]; then
    mv -f "${USER_BIN}/claude-raw" "${USER_BIN}/claude"
    echo -e "${GREEN}[✓]${NC} Восстановлен оригинальный бинарник ~/.local/bin/claude"
else
    rm -f "${USER_BIN}/claude"
fi

rm -f "${USER_BIN}/claude-desktop"
rm -f "${USER_BIN}/celltest"
rm -f "${USER_BIN}/claude-vpn"
rm -f "${TARGET_HOME}/.config/fish/functions/claude.fish"
rm -f "${TARGET_HOME}/.config/fish/functions/claude-desktop.fish"

echo -e "${GREEN}${BOLD}ClaudeCage успешно удалён.${NC}"
echo -e "Примечание: конфигурационный файл /etc/claude-vpn.conf сохранён для бэкапа."
