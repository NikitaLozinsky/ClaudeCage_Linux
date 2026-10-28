function cld-probe --description "Аудит сетевой видимости и логгер лазеек ClaudeCage"
    if test -x /usr/local/bin/cld-probe
        /usr/local/bin/cld-probe $argv
    else if test -x $HOME/.local/bin/cld-probe
        $HOME/.local/bin/cld-probe $argv
    else if test -x /usr/local/bin/claude-probe
        /usr/local/bin/claude-probe $argv
    else
        echo "cld-probe не найден в PATH" >&2
        return 1
    end
end

function claude-probe --description "Алиас для cld-probe"
    cld-probe $argv
end
