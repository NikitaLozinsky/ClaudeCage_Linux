#!/usr/bin/env bash
# ==============================================================================
# ClaudeCage Installer (Linux) v3.0 Stealth
# Automated deployment of kernel-level netns, nftables kill switch, systemd units
# zero-leak geo spoofing and stealth wrappers
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
echo "║      ClaudeCage v3.0: Linux Network Sandbox & Stealth Jail       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 1. Определение целевого пользователя
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_GROUP=$(id -gn "$TARGET_USER")

info "Целевой пользователь: ${BOLD}${TARGET_USER}${NC} (Home: ${TARGET_HOME})"
info "Каталог установки ClaudeCage: ${BOLD}${HERE}${NC}"

# 2. Проверка зависимостей
step "Проверка системных зависимостей"
MISSING_DEPS=()
for dep in ip nft bwrap setpriv xclip notify-send python3 ss; do
    if ! command -v "$dep" &>/dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    err "Отсутствуют необходимые системные утилиты: ${MISSING_DEPS[*]}"
    echo "Пожалуйста, установите их через менеджер пакетов:"
    echo "  Arch Linux: sudo pacman -S iproute2 nftables bubblewrap util-linux xclip libnotify python"
    echo "  Debian/Ubuntu: sudo apt install iproute2 nftables bubblewrap util-linux xclip libnotify-bin python3"
    echo "  Fedora: sudo dnf install iproute nftables bubblewrap util-linux xclip libnotify python3"
    exit 1
fi
info "Все обязательные системные зависимости найдены!"

if ! command -v dbus-run-session &>/dev/null; then
    warn "Рекомендуется утилита dbus-run-session (пакет dbus) для полной изоляции D-Bus"
fi
if ! command -v conntrack &>/dev/null; then
    warn "Утилита conntrack (пакет conntrack-tools) не найдена (необязательно, полезна для мгновенного сброса conntrack при падении VPN)"
fi
if [[ -n "${WAYLAND_DISPLAY:-}" ]] && ! command -v wl-copy &>/dev/null; then
    warn "Обнаружена сессия Wayland, но wl-copy не установлен (для X11 используется xclip)"
fi

# 3. Синтаксическая валидация скриптов перед копированием
step "Валидация синтаксиса скриптов"
for f in bin/claude-vpn bin/celltest bin/xdg-open-jail wrappers/claude wrappers/claude-desktop; do
    bash -n "$HERE/$f" || { err "Ошибка синтаксиса в $f"; exit 1; }
done
info "Синтаксис всех скриптов проверен!"

# 4. Установка системных бинарников
step "Установка системного оркестратора и перехватчиков"
sudo mkdir -p /usr/local/bin /usr/local/lib/claude-vpn

# Сброс старой клетки перед обновлением
if [[ -x /usr/local/bin/claude-vpn ]]; then
    warn "Обнаружена установленная версия claude-vpn: сбрасываю старое пространство..."
    sudo /usr/local/bin/claude-vpn --down >/dev/null 2>&1 || true
fi

sudo cp -f "$HERE/bin/claude-vpn" /usr/local/bin/claude-vpn
sudo chown root:root /usr/local/bin/claude-vpn
sudo chmod 0755 /usr/local/bin/claude-vpn
info "Установлен /usr/local/bin/claude-vpn (root:root 0755)"

sudo cp -f "$HERE/bin/xdg-open-jail" /usr/local/lib/claude-vpn/xdg-open-jail
sudo chown root:root /usr/local/lib/claude-vpn/xdg-open-jail
sudo chmod 0755 /usr/local/lib/claude-vpn/xdg-open-jail
info "Установлен /usr/local/lib/claude-vpn/xdg-open-jail (root:root 0755)"

# 5. Настройка безопасного sudoers с visudo
step "Настройка безопасного sudoers"
SUDOERS_FILE="/etc/sudoers.d/claude-vpn"
sudo mkdir -p /etc/sudoers.d

tmp_sudoers=$(mktemp)
cat << EOF_SUDO > "$tmp_sudoers"
# ClaudeCage v3.0 NOPASSWD execution for claude-vpn orchestrator and celltest
# !use_pty prevents TTY hijacking and LPE vulnerabilities
Defaults!/usr/local/bin/claude-vpn !use_pty
Defaults!/usr/local/bin/celltest !use_pty
${TARGET_USER} ALL=(root) NOPASSWD: /usr/local/bin/claude-vpn, /usr/local/bin/celltest
EOF_SUDO

if command -v visudo &>/dev/null && ! sudo visudo -cf "$tmp_sudoers" &>/dev/null; then
    rm -f "$tmp_sudoers"
    err "Сгенерированный файл sudoers не прошёл проверку visudo!"
    exit 1
fi

sudo cp -f "$tmp_sudoers" "$SUDOERS_FILE"
sudo chmod 0440 "$SUDOERS_FILE"
sudo chown root:root "$SUDOERS_FILE"
rm -f "$tmp_sudoers"
info "Настроен $SUDOERS_FILE для пользователя $TARGET_USER"

# 6. Определение интерфейса VPN и системный конфиг
step "Конфигурация сети и путей"
DETECTED_IFACE="amn0"
for iface in amn0 wg0 tun0 proton0; do
    if ip link show "$iface" &>/dev/null; then
        DETECTED_IFACE="$iface"
        break
    fi
done

SYS_CONF="/etc/claude-vpn.conf"
if [[ ! -f "$SYS_CONF" ]]; then
    sudo cp "$HERE/config/claude-vpn.conf.example" "$SYS_CONF"
    sudo sed -i "s|VPN_IFACE=.*|VPN_IFACE=\"${DETECTED_IFACE}\"|" "$SYS_CONF"
    sudo sed -i "s|CAGE_REPO_DIR=.*|CAGE_REPO_DIR=\"${HERE}\"|" "$SYS_CONF"
    sudo chown root:root "$SYS_CONF"
    sudo chmod 0644 "$SYS_CONF"
    info "Создан системный конфиг: $SYS_CONF (интерфейс: $DETECTED_IFACE, репозиторий: $HERE)"
else
    # Обновляем путь к репозиторию в существующем конфиге
    if grep -q "CAGE_REPO_DIR" "$SYS_CONF"; then
        sudo sed -i "s|CAGE_REPO_DIR=.*|CAGE_REPO_DIR=\"${HERE}\"|" "$SYS_CONF"
    else
        echo "CAGE_REPO_DIR=\"${HERE}\"" | sudo tee -a "$SYS_CONF" >/dev/null
    fi
    info "Существующий системный конфиг обновлён ($SYS_CONF)"
fi

# 7. Установка Systemd служб
step "Установка systemd служб (Fail-Closed Kill Switch & Watchdog)"
sudo cp -f "$HERE/systemd/claude-vpn.service" /etc/systemd/system/claude-vpn.service
sudo cp -f "$HERE/systemd/claude-vpn-watchdog.service" /etc/systemd/system/claude-vpn-watchdog.service
sudo systemctl daemon-reload
sudo systemctl enable claude-vpn.service >/dev/null 2>&1 || true
info "Установлены службы:"
info "  - /etc/systemd/system/claude-vpn.service (Before=network-pre.target)"
info "  - /etc/systemd/system/claude-vpn-watchdog.service (KillMode=control-group)"

# 8. Установка пользовательских обёрток
step "Установка пользовательских обёрток и интеграций"
USER_BIN="${TARGET_HOME}/.local/bin"
mkdir -p "$USER_BIN"

# Обёртка CLI claude
if [[ -e "${USER_BIN}/claude" ]] && ! grep -q "claude-vpn" "${USER_BIN}/claude" 2>/dev/null; then
    info "Сохраняю оригинальный бинарник claude в claude-raw..."
    mv -f "${USER_BIN}/claude" "${USER_BIN}/claude-raw"
fi
cp -f "$HERE/wrappers/claude" "${USER_BIN}/claude"
chmod +x "${USER_BIN}/claude"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_BIN}/claude"
info "Установлена обёртка CLI: ${USER_BIN}/claude"

# Обёртка GUI claude-desktop
cp -f "$HERE/wrappers/claude-desktop" "${USER_BIN}/claude-desktop"
chmod +x "${USER_BIN}/claude-desktop"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_BIN}/claude-desktop"
info "Установлена обёртка GUI: ${USER_BIN}/claude-desktop"

# Диагностическая утилита celltest
cp -f "$HERE/bin/celltest" "${USER_BIN}/celltest"
chmod +x "${USER_BIN}/celltest"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_BIN}/celltest"
sudo cp -f "$HERE/bin/celltest" /usr/local/bin/celltest
sudo chmod 0755 /usr/local/bin/celltest
info "Установлена утилита диагностики celltest в ${USER_BIN}/celltest и /usr/local/bin/celltest"

# Fish функции
if command -v fish &>/dev/null; then
    FISH_FUNC_DIR="${TARGET_HOME}/.config/fish/functions"
    mkdir -p "$FISH_FUNC_DIR"
    cp -f "$HERE/wrappers/fish/"*.fish "$FISH_FUNC_DIR/"
    chown -R "${TARGET_USER}:${TARGET_GROUP}" "$FISH_FUNC_DIR"
    info "Установлены fish-функции: claude, claude-desktop"
fi

# Ярлык приложения (.desktop)
DESKTOP_DIR="${TARGET_HOME}/.local/share/applications"
if [[ -d "$HERE/desktop" ]]; then
    mkdir -p "$DESKTOP_DIR"
    cp -f "$HERE/desktop/"*.desktop "$DESKTOP_DIR/" 2>/dev/null || true
    chown -R "${TARGET_USER}:${TARGET_GROUP}" "$DESKTOP_DIR" 2>/dev/null || true
    info "Обновлен ярлык меню приложений"
fi

# 9. Запуск клетки
step "Инициализация сетевого пространства"
sudo /usr/local/bin/claude-vpn --up || warn "Не удалось автоматически поднять claude-vpn (проверьте статус VPN)"

step "Итог установки"
echo -e "${GREEN}${BOLD}Установка ClaudeCage v3.0 успешно завершена!${NC}"
echo ""
echo -e "Для комплексной диагностики защиты запустите:"
echo -e "  ${CYAN}celltest${NC}"
echo ""
echo -e "Для запуска Claude в изолированной невидимой песочнице:"
echo -e "  ${CYAN}claude${NC}          (CLI версия)"
echo -e "  ${CYAN}claude-desktop${NC}  (Десктопная версия)"
echo ""
