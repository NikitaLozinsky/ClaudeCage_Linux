function claude-probe --description "Аудит сетевой видимости и логгер лазеек ClaudeCage"
    if test -x /usr/local/bin/claude-probe
        /usr/local/bin/claude-probe $argv
    else if test -x $HOME/.local/bin/claude-probe
        $HOME/.local/bin/claude-probe $argv
    else
        echo "claude-probe не найден в PATH" >&2
        return 1
    end
end
