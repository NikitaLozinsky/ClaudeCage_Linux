function claude --description 'Run Claude Code CLI inside isolated stealth network namespace'
    if ip -4 -o addr show dev enp3s0 2>/dev/null | grep -q '10\.200\.1\.2/24'; or ip link show veth_ns >/dev/null 2>&1
        if test -x "$HOME/.local/bin/claude-raw"
            exec "$HOME/.local/bin/claude-raw" $argv
        else if test -x "$HOME/.local/bin/claude"; and not grep -q "cld-cage" "$HOME/.local/bin/claude" 2>/dev/null
            exec "$HOME/.local/bin/claude" $argv
        else if test -x "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/bin/claude"
            exec "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/bin/claude" $argv
        else if test -x "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/cli.js"
            exec "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/cli.js" $argv
        else if test -x "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
            exec "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe" $argv
        else
            echo "Error: raw claude binary not found" >&2
            return 127
        end
    end

    switch "$PWD"
        case "*ClaudeCage*" "*claude-vpn*" "*claudecage*" "*cld-cage*" "*/.netif-core*" "*/.netif-core"
            echo "ОШИБКА БЕЗОПАСНОСТИ: Запуск Claude Code внутри каталога ClaudeCage запрещён!" >&2
            echo "Перейдите в каталог вашего рабочего проекта." >&2
            return 1
    end

    sudo -n /usr/local/bin/cld-cage claude $argv
    set -l status_code $status
    if test $status_code -ne 0
        echo "Ошибка запуска Claude Code внутри клетки (код $status_code)." >&2
        echo "Убедитесь, что настроен /etc/sudoers.d/cld-cage (запустите install.sh)." >&2
        return $status_code
    end
end
