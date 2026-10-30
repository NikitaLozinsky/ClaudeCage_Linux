#!/bin/bash
# ============================================================
# Stealth Status Indicator for Polybar / bspwm
# Usage in polybar config:
#   [module/cld_status]
#   type = custom/script
#   exec = ~/.local/bin/cld-status.sh
#   interval = 3
# ============================================================
set -u

STATE_DIR="/run/systemd/netif-cage"

if ! ip netns list 2>/dev/null | grep -q "^cld_net\b"; then
    echo "%{F#707880}⭕ Claude: Off%{F-}"
    exit 0
fi

# Проверка активного маршрута туннеля в таблице 200
if ip route show table 200 2>/dev/null | grep -q "^default dev"; then
    cc=$(cat "$STATE_DIR/cached_cc" 2>/dev/null || echo "")
    if [[ -z "$cc" && -f "$STATE_DIR/cached_tz" ]]; then
        cc=$(cat "$STATE_DIR/cached_tz" 2>/dev/null | awk -F/ '{print $NF}')
    fi
    [[ -n "$cc" ]] && cc=" ($cc)"
    echo "%{F#A3BE8C}🔒 Claude: VPN${cc}%{F-}"
else
    echo "%{F#BF616A}🛑 Claude: Isolated%{F-}"
fi
