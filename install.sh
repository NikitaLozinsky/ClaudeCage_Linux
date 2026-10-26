#!/usr/bin/env bash
# ==============================================================================
# ClaudeCage Installer (Linux)
# Automated deployment of kernel-level netns, nftables kill switch and wrappers
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1" >&2; }
step()  { echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${NC}"; }

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║          ClaudeCage: Linux Network Sandbox & Jail Installer     ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. Определение целевого пользователя
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_GROUP=$(id -gn "$TARGET_USER")

info "Целевой пользователь: ${BOLD}${TARGET_USER}${NC} (Home: ${TARGET_HOME})"

# 2. Проверка зависимостей
step "Проверка системных зависимостей"
MISSING_DEPS=()
for dep in ip nft bwrap setpriv xclip notify-send; do
    if ! command -v "$dep" &>/dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    err "Отсутствуют необходимые системные утилиты: ${MISSING_DEPS[*]}"
    echo "Пожалуйста, установите их через менеджер пакетов вашего дистрибутива:"
    echo "  Arch Linux: sudo pacman -S iproute2 nftables bubblewrap util-linux xclip libnotify"
    echo "  Debian/Ubuntu: sudo apt install iproute2 nftables bubblewrap util-linux xclip libnotify-bin"
    echo "  Fedora: sudo dnf install iproute nftables bubblewrap util-linux xclip libnotify"
    exit 1
fi
info "Все ключевые зависимости найдены!"

if ! command -v dbus-run-session &>/dev/null; then
    warn "dbus-run-session не найден. Рекомендуется установить пакет dbus для полной изоляции D-Bus."
fi

# 3. Установка системных бинарников
step "Установка оркестратора и перехватчиков"
sudo mkdir -p /usr/local/bin /usr/local/lib/claude-vpn
sudo cp -f bin/claude-vpn /usr/local/bin/claude-vpn
sudo chown root:root /usr/local/bin/claude-vpn
sudo chmod 0755 /usr/local/bin/claude-vpn
info "Установлен /usr/local/bin/claude-vpn (root:root 0755)"

sudo cp -f bin/xdg-open-jail /usr/local/lib/claude-vpn/xdg-open-jail
sudo chown root:root /usr/local/lib/claude-vpn/xdg-open-jail
sudo chmod 0755 /usr/local/lib/claude-vpn/xdg-open-jail
info "Установлен /usr/local/lib/claude-vpn/xdg-open-jail (root:root 0755)"

# 4. Настройка sudoers
step "Настройка безопасного sudoers без LPE"
SUDOERS_FILE="/etc/sudoers.d/claude-vpn"
sudo mkdir -p /etc/sudoers.d
sudo bash -c "cat << 'EOF_SUDO' > '$SUDOERS_FILE'
Defaults!/usr/local/bin/claude-vpn !use_pty
${TARGET_USER} ALL=(root) NOPASSWD: /usr/local/bin/claude-vpn
EOF_SUDO"
sudo chmod 0440 "$SUDOERS_FILE"
info "Настроен $SUDOERS_FILE для пользователя $TARGET_USER"

# 5. Определение VPN-интерфейса
step "Конфигурация сети и VPN"
DETECTED_IFACE="amn0"
for iface in amn0 wg0 tun0 proton0; do
    if ip link show "$iface" &>/dev/null; then
        DETECTED_IFACE="$iface"
        break
    fi
done

SYS_CONF="/etc/claude-vpn.conf"
if [[ ! -f "$SYS_CONF" ]]; then
    sudo cp config/claude-vpn.conf.example "$SYS_CONF"
    sudo sed -i "s/VPN_IFACE=\"amn0\"/VPN_IFACE=\"${DETECTED_IFACE}\"/" "$SYS_CONF"
    sudo chown root:root "$SYS_CONF"
    sudo chmod 0644 "$SYS_CONF"
    info "Создан системный конфиг: $SYS_CONF (интерфейс: $DETECTED_IFACE)"
else
    info "Существующий системный конфиг сохранён: $SYS_CONF"
fi

CONF_DIR="${TARGET_HOME}/.config"
CONF_FILE="${CONF_DIR}/claude-vpn.conf"
mkdir -p "$CONF_DIR"

if [[ ! -f "$CONF_FILE" ]]; then
    cp config/claude-vpn.conf.example "$CONF_FILE"
    sed -i "s/VPN_IFACE=\"amn0\"/VPN_IFACE=\"${DETECTED_IFACE}\"/" "$CONF_FILE"
    chown "${TARGET_USER}:${TARGET_GROUP}" "$CONF_FILE"
    info "Создан пользовательский конфиг: $CONF_FILE"
else
    info "Существующий конфиг сохранён: $CONF_FILE"
fi

# 6. Установка пользовательских обёрток
step "Установка обёрток и интеграций"
USER_BIN="${TARGET_HOME}/.local/bin"
mkdir -p "$USER_BIN"

# Обратная совместимость для claude-vpn
ln -sf /usr/local/bin/claude-vpn "${USER_BIN}/claude-vpn"

# Обёртка CLI claude
if [[ -e "${USER_BIN}/claude" ]] && ! grep -q "claude-vpn" "${USER_BIN}/claude" 2>/dev/null; then
    info "Сохраняю оригинальный бинарник claude в claude-raw..."
    mv -f "${USER_BIN}/claude" "${USER_BIN}/claude-raw"
fi
cp -f wrappers/claude "${USER_BIN}/claude"
chmod +x "${USER_BIN}/claude"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_BIN}/claude"
info "Установлена обёртка CLI: ${USER_BIN}/claude"

# Обёртка GUI claude-desktop
cp -f wrappers/claude-desktop "${USER_BIN}/claude-desktop"
chmod +x "${USER_BIN}/claude-desktop"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_BIN}/claude-desktop"
info "Установлена обёртка GUI: ${USER_BIN}/claude-desktop"

# Диагностическая утилита celltest
cp -f bin/celltest "${USER_BIN}/celltest"
chmod +x "${USER_BIN}/celltest"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_BIN}/celltest"
info "Установлена утилита диагностики: ${USER_BIN}/celltest"

# Fish функции (если fish установлен)
if command -v fish &>/dev/null; then
    FISH_FUNC_DIR="${TARGET_HOME}/.config/fish/functions"
    mkdir -p "$FISH_FUNC_DIR"
    cp -f wrappers/fish/*.fish "$FISH_FUNC_DIR/"
    chown -R "${TARGET_USER}:${TARGET_GROUP}" "$FISH_FUNC_DIR"
    info "Установлены fish-функции: claude, claude-desktop"
fi

# Ярлык приложения (.desktop)
DESKTOP_DIR="${TARGET_HOME}/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cp -f desktop/com.anthropic.Claude.desktop "$DESKTOP_DIR/"
chown -R "${TARGET_USER}:${TARGET_GROUP}" "$DESKTOP_DIR"
info "Обновлен ярлык меню приложений: $DESKTOP_DIR/com.anthropic.Claude.desktop"

# 7. Systemd служба (опционально)
step "Systemd служба автозапуска"
sudo cp -f systemd/claude-vpn.service /etc/systemd/system/claude-vpn.service
sudo systemctl daemon-reload
info "Установлен /etc/systemd/system/claude-vpn.service"

# 8. Перезапуск активного сетевого пространства (если было запущено)
if ip netns list 2>/dev/null | grep -qw "claude_vpn"; then
    step "Обновление активного сетевого пространства"
    info "Обнаружено активное сетевое пространство claude_vpn. Применяем обновленные правила ядра..."
    /usr/local/bin/claude-vpn --down >/dev/null 2>&1 || true
    /usr/local/bin/claude-vpn --up || warn "Не удалось автоматически перезапустить claude_vpn"
    info "Сетевое пространство успешно перезапущено с новыми правилами ядра!"
fi

step "Итог установки"
echo -e "${GREEN}${BOLD}Установка ClaudeCage успешно завершена!${NC}"
echo ""
echo -e "Для проверки состояния изоляции запустите:"
echo -e "  ${CYAN}celltest${NC}"
echo ""
echo -e "Для запуска Claude в изолированной клетке используйте привычные команды:"
echo -e "  ${CYAN}claude${NC}          (CLI версия)"
echo -e "  ${CYAN}claude-desktop${NC}  (Десктопное приложение)"
echo ""
