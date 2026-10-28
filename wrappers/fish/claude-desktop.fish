function claude-desktop --description 'Run Claude Desktop inside isolated stealth network namespace'
    if ip link show veth_ns >/dev/null 2>&1
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
