function claude-desktop --description 'Run Claude Desktop inside isolated stealth network namespace'
    if ip -4 -o addr show dev enp3s0 2>/dev/null | grep -q '10\.200\.1\.2/24'; or ip link show veth_ns >/dev/null 2>&1
        if test -x /usr/bin/claude-desktop
            exec /usr/bin/claude-desktop $argv
        else if test -x /usr/lib/claude-desktop/claude-desktop
            exec /usr/lib/claude-desktop/claude-desktop $argv
        else
            echo "Error: claude-desktop binary not found" >&2
            return 127
        end
    end

    sudo /usr/local/bin/cld-cage claude-desktop $argv
end
