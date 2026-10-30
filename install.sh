#!/usr/bin/env bash
# ==============================================================================
# ClaudeCage Installer (Linux) v3.1 Stealth
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
echo "║      ClaudeCage v3.1: Linux Network Sandbox & Stealth Jail       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 1. Определение целевого пользователя
TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$TARGET_USER" == "root" ]]; then
    DETECTED_USER=$(find /home -maxdepth 1 -mindepth 1 -type d -not -name "root" -printf "%f\n" 2>/dev/null | head -n1 || echo "")
    if [[ -n "$DETECTED_USER" ]]; then
        TARGET_USER="$DETECTED_USER"
    fi
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_GROUP=$(id -gn "$TARGET_USER")

# Опциональная миграция каталога репозитория в ~/.netif-core для 100% сокрытия в mountinfo
STEALTH_DEST="${TARGET_HOME}/.netif-core"
if [[ "${1:-}" == "--migrate-stealth" || "${1:-}" == "--stealth" ]]; then
    if [[ "$HERE" != "$STEALTH_DEST" ]]; then
        info "Перемещение репозитория из $HERE в нейтральный каталог $STEALTH_DEST..."
        mv -T "$HERE" "$STEALTH_DEST"
        HERE="$STEALTH_DEST"
        chown -R "${TARGET_USER}:${TARGET_GROUP}" "$STEALTH_DEST" 2>/dev/null || true
        info "Репозиторий успешно перемещён в $STEALTH_DEST!"
    fi
fi

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
for f in bin/cld-cage bin/celltest bin/xdg-open-jail bin/cld-probe wrappers/claude wrappers/claude-desktop wrappers/polybar-status.sh; do
    if [[ $f == *.py || $f == *probe ]]; then
        python3 -c "import ast, sys; ast.parse(open(sys.argv[1], 'rb').read())" "$HERE/$f" || { err "Ошибка синтаксиса в $f"; exit 1; }
    else
        bash -n "$HERE/$f" || { err "Ошибка синтаксиса в $f"; exit 1; }
    fi
done
sudo rm -rf "$HERE/bin/__pycache__" "$HERE/__pycache__" 2>/dev/null || true
info "Синтаксис всех скриптов проверен!"

# 4. Установка системных бинарников
step "Установка системного оркестратора и перехватчиков"
sudo mkdir -p /usr/local/bin /usr/local/lib/cld-cage

# Остановка старых служб claude-vpn (миграция на cld-cage)
sudo systemctl stop cld-cage-watchdog.service cld-cage.service claude-vpn-watchdog.service claude-vpn.service 2>/dev/null || true
sudo systemctl disable claude-vpn-watchdog.service claude-vpn.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/claude-vpn* 2>/dev/null || true

# Сброс старой клетки перед обновлением
if [[ -x /usr/local/bin/cld-cage ]]; then
    info "Корректный перезапуск сети cld-cage..."
    sudo /usr/local/bin/cld-cage --down >/dev/null 2>&1 || true
elif [[ -x /usr/local/bin/claude-vpn ]]; then
    info "Обнаружена старая версия claude-vpn: корректная остановка перед миграцией на cld-cage..."
    sudo /usr/local/bin/claude-vpn --down >/dev/null 2>&1 || true
fi

sudo cp -f "$HERE/bin/cld-cage" /usr/local/bin/cld-cage
sudo chown root:root /usr/local/bin/cld-cage
sudo chmod 0755 /usr/local/bin/cld-cage
sudo ln -sf cld-cage /usr/local/bin/claude-vpn
info "Установлен /usr/local/bin/cld-cage (алиас: /usr/local/bin/claude-vpn)"

sudo cp -f "$HERE/bin/xdg-open-jail" /usr/local/lib/xdg-desktop-handler
sudo chown root:root /usr/local/lib/xdg-desktop-handler
sudo chmod 0755 /usr/local/lib/xdg-desktop-handler
sudo rm -rf /usr/local/lib/cld-cage /usr/local/lib/claude-vpn /run/cld-cage 2>/dev/null || true
info "Установлен /usr/local/lib/xdg-desktop-handler (root:root 0755)"

# 5. Настройка безопасного sudoers с visudo
step "Настройка безопасного sudoers"
SUDOERS_FILE="/etc/sudoers.d/cld-cage"
sudo mkdir -p /etc/sudoers.d

tmp_sudoers=$(mktemp)
cat << EOF_SUDO > "$tmp_sudoers"
# ClaudeCage v3.1 NOPASSWD execution for cld-cage orchestrator, celltest and cld-probe
# Defaults env_reset and !use_pty prevent environment injection, TTY hijacking and LPE vulnerabilities
Defaults env_reset
Defaults!/usr/local/bin/cld-cage !use_pty, !requiretty
Defaults!/usr/local/bin/claude-vpn !use_pty, !requiretty
Defaults!/usr/local/bin/celltest !use_pty, !requiretty
Defaults!/usr/local/bin/cld-probe !use_pty, !requiretty
Defaults!/usr/local/bin/claude-probe !use_pty, !requiretty
${TARGET_USER} ALL=(root) NOPASSWD: /usr/local/bin/cld-cage, /usr/local/bin/claude-vpn, /usr/local/bin/celltest, /usr/local/bin/cld-probe, /usr/local/bin/claude-probe
EOF_SUDO

if command -v visudo &>/dev/null && ! sudo visudo -cf "$tmp_sudoers" &>/dev/null; then
    rm -f "$tmp_sudoers"
    err "Сгенерированный файл sudoers не прошёл проверку visudo!"
    exit 1
fi

sudo cp -f "$tmp_sudoers" "$SUDOERS_FILE"
sudo chmod 0440 "$SUDOERS_FILE"
sudo chown root:root "$SUDOERS_FILE"
sudo rm -f /etc/sudoers.d/claude-vpn 2>/dev/null || true
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

SYS_CONF="/etc/cld-cage.conf"
if [[ ! -f "$SYS_CONF" && -f "/etc/claude-vpn.conf" ]]; then
    info "Миграция существующего конфига /etc/claude-vpn.conf в $SYS_CONF..."
    sudo cp -f "/etc/claude-vpn.conf" "$SYS_CONF"
fi

if [[ ! -f "$SYS_CONF" ]]; then
    sudo cp "$HERE/config/cld-cage.conf.example" "$SYS_CONF"
    sudo sed -i "s|VPN_IFACE=.*|VPN_IFACE=\"${DETECTED_IFACE}\"|" "$SYS_CONF"
    sudo sed -i "s|CAGE_REPO_DIR=.*|CAGE_REPO_DIR=\"${HERE}\"|" "$SYS_CONF"
    sudo chown root:root "$SYS_CONF"
    sudo chmod 0644 "$SYS_CONF"
    info "Создан системный конфиг: $SYS_CONF (интерфейс: $DETECTED_IFACE, таймзона: auto, DNS: auto)"
else
    # Обновляем путь к репозиторию в существующем конфиге
    if grep -q "CAGE_REPO_DIR" "$SYS_CONF"; then
        sudo sed -i "s|CAGE_REPO_DIR=.*|CAGE_REPO_DIR=\"${HERE}\"|" "$SYS_CONF"
    else
        echo "CAGE_REPO_DIR=\"${HERE}\"" | sudo tee -a "$SYS_CONF" >/dev/null
    fi
    # Обновляем устаревший хардкод таймзоны Amsterdam на динамический auto
    if grep -q "Europe/Amsterdam" "$SYS_CONF"; then
        sudo sed -i 's/CLAUDE_TZ="Europe\/Amsterdam"/CLAUDE_TZ="auto"/g; s/CLD_TZ="Europe\/Amsterdam"/CLD_TZ="auto"/g' "$SYS_CONF"
        info "Обновлена таймзона в $SYS_CONF: CLD_TZ=\"auto\" (динамическое определение под сервер VPN)"
    fi
    info "Существующий системный конфиг обновлён ($SYS_CONF)"
fi

if [[ "$HERE" =~ ClaudeCage|claude-vpn|claudecage ]]; then
    warn "Каталог репозитория ($HERE) содержит имя ClaudeCage."
    info "Для 100% сокрытия имени из /proc/self/mountinfo запустите: sudo ./install.sh --stealth"
    info "(или вручную: mv $HERE ${TARGET_HOME}/.netif-core && cd ${TARGET_HOME}/.netif-core && sudo ./install.sh)"
fi

# 7. Установка Systemd служб
step "Установка systemd служб (Fail-Closed Kill Switch & Watchdog)"
sudo cp -f "$HERE/systemd/cld-cage.service" /etc/systemd/system/cld-cage.service
sudo cp -f "$HERE/systemd/cld-cage-watchdog.service" /etc/systemd/system/cld-cage-watchdog.service
sudo systemctl daemon-reload
sudo systemctl enable cld-cage.service >/dev/null 2>&1 || true
info "Установлены службы:"
info "  - /etc/systemd/system/cld-cage.service (Before=network-pre.target)"
info "  - /etc/systemd/system/cld-cage-watchdog.service (KillMode=control-group)"

# 8. Установка пользовательских обёрток
step "Установка пользовательских обёрток и интеграций"
USER_BIN="${TARGET_HOME}/.local/bin"
mkdir -p "$USER_BIN"

# Обёртка CLI claude
if [[ -e "${USER_BIN}/claude" ]] && ! grep -q -E "cld-cage|claude-vpn" "${USER_BIN}/claude" 2>/dev/null; then
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

# Индикатор статуса для polybar / bspwm
if [[ -f "$HERE/wrappers/polybar-status.sh" ]]; then
    cp -f "$HERE/wrappers/polybar-status.sh" "${USER_BIN}/cld-status.sh"
    chmod +x "${USER_BIN}/cld-status.sh"
    chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_BIN}/cld-status.sh"
    sudo cp -f "$HERE/wrappers/polybar-status.sh" /usr/local/bin/cld-status
    sudo chmod 0755 /usr/local/bin/cld-status
    info "Установлен скрипт статуса для Polybar/bspwm: ${USER_BIN}/cld-status.sh (/usr/local/bin/cld-status)"
fi

# Диагностическая утилита celltest (устанавливается только в /usr/local/bin для скрытности от клетки)
sudo cp -f "$HERE/bin/celltest" /usr/local/bin/celltest
sudo chmod 0755 /usr/local/bin/celltest
rm -f "${USER_BIN}/celltest" 2>/dev/null || true
info "Установлена утилита диагностики celltest в /usr/local/bin/celltest"

# Аудитор и логгер сетевой видимости cld-probe (устанавливается только в /usr/local/bin для скрытности от клетки)
sudo cp -f "$HERE/bin/cld-probe" /usr/local/bin/cld-probe
sudo chmod 0755 /usr/local/bin/cld-probe
sudo ln -sf cld-probe /usr/local/bin/claude-probe
rm -f "${USER_BIN}/cld-probe" "${USER_BIN}/claude-probe" "${USER_BIN}/claude-vpn" 2>/dev/null || true
info "Установлен логгер и аудитор cld-probe в /usr/local/bin/cld-probe"

# Fish функции
if command -v fish &>/dev/null; then
    FISH_FUNC_DIR="${TARGET_HOME}/.config/fish/functions"
    mkdir -p "$FISH_FUNC_DIR"
    cp -f "$HERE/wrappers/fish/"*.fish "$FISH_FUNC_DIR/"
    chown -R "${TARGET_USER}:${TARGET_GROUP}" "$FISH_FUNC_DIR"
    info "Установлены fish-функции: claude, claude-desktop, cld-probe"
fi

# Ярлык приложения (.desktop)
DESKTOP_DIR="${TARGET_HOME}/.local/share/applications"
if [[ -d "$HERE/desktop" ]]; then
    mkdir -p "$DESKTOP_DIR"
    for dtf in "$HERE/desktop/"*.desktop; do
        if [[ -f "$dtf" ]]; then
            sed "s|^Exec=.*|Exec=${USER_BIN}/claude-desktop %u|g" "$dtf" > "${DESKTOP_DIR}/${dtf##*/}"
        fi
    done
    chown -R "${TARGET_USER}:${TARGET_GROUP}" "$DESKTOP_DIR" 2>/dev/null || true
    info "Обновлен ярлык меню приложений"
fi

# 9. Запуск клетки
step "Инициализация сетевого пространства"
sudo /usr/local/bin/cld-cage --up || warn "Не удалось автоматически поднять cld-cage (проверьте статус VPN)"

step "Итог установки"
echo -e "${GREEN}${BOLD}Установка ClaudeCage v3.1 успешно завершена!${NC}"
echo ""
echo -e "Для комплексной диагностики защиты запустите:"
echo -e "  ${CYAN}celltest${NC}        (Проверка конфигурации ядра, nftables и watchdog)"
echo -e "  ${CYAN}cld-probe${NC}       (Аудит сетевой видимости и логгер лазеек глазами Claude)"
echo ""
echo -e "Для живого мониторинга соединений клетки в реальном времени:"
echo -e "  ${CYAN}cld-probe --monitor${NC}"
echo "  (или cld-cage --monitor)"
echo ""
echo -e "Для запуска Claude в изолированной невидимой песочнице:"
echo -e "  ${CYAN}claude${NC}          (CLI версия)"
echo -e "  ${CYAN}claude-desktop${NC}  (Десктопная версия)"
echo ""
