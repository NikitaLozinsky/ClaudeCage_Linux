# 🧠 ClaudeCage v3.0 — Gemini Internal Knowledge Base & Operational Guide

> **Файл предназначен исключительно для Gemini (ИИ-агента) в качестве контекстной шпаргалки, архитектурного справочника и руководства по обслуживанию проекта ClaudeCage.**

---

## 📌 1. Архитектурный базис проекта

### Назначение:
Полная изоляция процессов **Claude Code (CLI)** и **Claude Desktop (Electron)** от реальных сетевых и региональных реквизитов хоста (IP, DNS, WebRTC, интерфейсы, часовой пояс, русская локаль РФ). Обеспечивает 100% обход антифрода Anthropic и аппаратный Fail-Closed Kill Switch при сбоях VPN.

### Ключевые компоненты и пути в системе:

| Компонент | Расположение на хосте | Назначение / Особенности |
|---|---|---|
| **Оркестратор** | `/usr/local/bin/cld-cage` | Главный скрипт: bwrap, netns, policy routing, nftables, watchdog. (Алиас: `claude-vpn`) |
| **Аудитор / Логгер** | `/usr/local/bin/cld-probe` | Python 3 инструмент аудита 8 векторов атак и живой монитор трафика клетки (`--monitor`). (Алиас: `claude-probe`) |
| **Диагностика** | `/usr/local/bin/celltest` | Проверка ядра, netns, nftables, watchdog, concealment изнутри и снаружи. |
| **Перехватчик URL** | `/usr/local/lib/cld-cage/xdg-open-jail` | Заменяет браузер внутри клетки: копирует URL в буфер хоста и шлёт notification. |
| **Конфигурация** | `/etc/cld-cage.conf` | root:root 0644. Парсинг регулярками (без `source`). Fallback: `/etc/claude-vpn.conf`. |
| **Sudoers** | `/etc/sudoers.d/cld-cage` | NOPASSWD с `!use_pty` для `cld-cage`, `celltest`, `cld-probe`. |
| **Systemd Unit (Core)** | `/etc/systemd/system/cld-cage.service` | `Before=network-pre.target`, `Type=oneshot`, поднимает netns до сети хоста. |
| **Systemd Unit (WD)** | `/etc/systemd/system/cld-cage-watchdog.service` | `KillMode=control-group`, мониторит Netlink-события VPN-туннеля. |
| **CLI Wrapper** | `~/.local/bin/claude` | Защита от запуска в папке клетки + вызов `sudo cld-cage claude`. |
| **GUI Wrapper** | `~/.local/bin/claude-desktop` | Вызов `sudo cld-cage claude-desktop`. |
| **Fish Functions** | `~/.config/fish/functions/` | `claude.fish`, `claude-desktop.fish`, `cld-probe.fish`. |
| **Директория логов** | `~/.local/state/cld-cage/` | `latest_audit.log`, `latest_audit.json`, `traffic_YYYY-MM-DD.log`. |

---

## 🔒 2. Стелс и Защита от Обнаружения (Anti-Cage-Detection)

Чтобы запущенный Claude (особенно Claude Code с доступом к bash) **не догадался**, что находится внутри клетки:

1. **Имя бинарников и служб:** Используется нейтральный префикс `cld-cage` / `cld-probe` / `cld_net` вместо `claude-vpn`, чтобы в `ps aux` не светилось ключевое слово «claude-vpn».
2. **Сокрытие репозитория клетки:** Каталог `$CAGE_REPO_DIR` (и любые `*ClaudeCage*` в `$HOME`) монтируются внутри bwrap как пустые `tmpfs`. Если агент сделает `ls /home/milk13/ClaudeCage_Linux`, он увидит пустую директорию.
3. **Оверлейная зачистка `/etc` и `/usr/local/bin`:** В оверлее удаляются все следы `cld-cage*`, `claude-vpn*`, `celltest*`, `cld-probe*`, `/etc/systemd/system/cld-cage*`.
4. **Маскировка `/sys/class/net`:** Смонтирован `tmpfs`, созданы только директории `lo` и `veth_ns`. Физические `wlan0`, `eth0`, `docker0` и аппаратные MAC-адреса хоста не видны.
5. **Сохранение реального Hostname:** Внутри песочницы используется настоящий hostname хоста (`cat /proc/sys/kernel/hostname`), а не маркеры вроде `claude-jail` или `sandbox`.
6. **Защита в точке входа (`wrappers/claude`):** Если текущий каталог `$PWD` содержит путь к репозиторию ClaudeCage, запуск прерывается с ошибкой, чтобы агент не прочитал исходники клетки.

---

## 🌍 3. Антифрод и Нулевая Утечка Региона (РФ $\rightarrow$ VPN)

1. **/etc/localtime:** В оверлее `/etc` симлинк `/etc/localtime` принудительно направлен на `/usr/share/zoneinfo/$CLD_TZ` (по умолчанию `Europe/Amsterdam`). Node.js `Intl.DateTimeFormat().resolvedOptions().timeZone` возвращает таймзону VPN.
2. **/etc/locale.conf:** Спуфится на `LANG=en_US.UTF-8`, `LC_ALL=en_US.UTF-8`.
3. **/etc/vconsole.conf:** Спуфится на `KEYMAP=us`.
4. **Окружение:** Вычищаются переменные `LC_*`, `LANG`, `TZ`, `SSH_AUTH_SOCK`.

---

## 🧱 4. Сетевая топология и Hard Kill Switch

* **Сетевой Namespace (`cld_net`):**
  * Виртуальная пара: `veth_host (10.200.1.1/24)` на хосте $\leftrightarrow$ `veth_ns (10.200.1.2/24)` в netns.
  * IPv6 внутри netns выключен аппаратно (`disable_ipv6=1`).
* **Policy Routing (Таблица 200, Priority 100):**
  * `ip rule add iif veth_host lookup 200 pref 100`
  * `ip route add default dev $VPN_IFACE table 200 metric 10`
  * `ip route add unreachable default table 200 metric 9999` (Fail-Closed на уровне ядра: при падении интерфейса туннеля ядро не переключается на шлюз хоста, а сразу отбивает пакеты).
* **nftables (`cld_cage_nat`):**
  * `iifname veth_host oifname != "$VPN_IFACE" counter drop` — **строго выше** любого conntrack accept!
  * `dnat ip to $VPN_DNS:53` — перехват любого DNS-запроса на резолвер VPN.
  * `mss clamping` — автоматическая подгонка MTU пакетов.
* **Watchdog демон (`cld-cage --watchdog-loop`):**
  * Слушает Netlink `ip -o monitor link addr dev $VPN_IFACE`.
  * При падении флагов `UP/LOWER_UP` немедленно снимает маршрут и вызывает `ss -K -tu 'not dst 127.0.0.0/8'`, разрывая активные сокеты, но **не трогая 127.0.0.1** (сохраняя жизнь MCP-серверам).

---

## 🛠️ 5. Оперативная шпаргалка команд

```bash
# Управление клеткой
cld-cage --status         # Показать статус сети, VPN, routing и счётчики дропов
cld-cage --up             # Принудительно поднять netns, routing, nftables и watchdog
cld-cage --down           # Полный сброс netns, правил nftables и остановка watchdog
cld-cage --monitor        # Живой перехват сетевых соединений клетки (conntrack/ss)

# Аудит и логгер (cld-probe)
cld-probe                 # Комплексный аудит 8 векторов атак изнутри клетки
cld-probe --monitor       # Запуск живого мониторинга трафика с записью в файл
cld-probe --desktop       # Аудит профиля Electron/WebRTC
cld-probe --cli           # Аудит профиля Claude Code CLI
cld-probe --json          # JSON вывод отчета

# Административная диагностика
celltest                  # Комплексный тест ядра, nftables, concealment и окружения

# Применение изменений после правок в репозитории
sudo ./install.sh         # ВСЕГДА запускать после изменений в bin/ или systemd!
```

---

## ⚠️ 6. Важные грабли и памятка для агента (Gotchas)

1. **Не забывать про `install.sh`:** Если ты правишь код в `bin/cld-cage`, `bin/celltest` или `bin/cld-probe`, эти изменения находятся **только в git-репозитории**. Системные бинарники лежат в `/usr/local/bin/`. Чтобы система их увидела, нужно выполнить `sudo ./install.sh`.
2. **Запуск Claude из папки репозитория:** Обёртка `claude` блокирует запуск внутри `/home/milk13/ClaudeCage_Linux`. Для тестирования или работы нужно переходить в нейтральную директорию (например, `cd /tmp` или `cd ~`).
3. **Сохранение прав sudoers:** Файл `/etc/sudoers.d/cld-cage` даёт `NOPASSWD` строго на `/usr/local/bin/cld-cage`, `/usr/local/bin/celltest`, `/usr/local/bin/cld-probe`. Сам `install.sh` требует ввода пароля sudo пользователя milk13.
4. **Обратная совместимость:** Все старые команды `claude-vpn` и `claude-probe` сохранены в виде символических ссылок на хосте, поэтому случайный ввод старой команды не вызовет ошибку.
