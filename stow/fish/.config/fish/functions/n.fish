function n --description 'Neovim; with no arguments, pick the files in yazi first'
    if test (count $argv) -gt 0
        command nvim $argv
        return
    end

    if not type -q yazi
        command nvim
        return
    end

    set -l tmp (mktemp)
    command yazi --chooser-file=$tmp
    set -l picked (cat $tmp 2>/dev/null)
    rm -f $tmp

    if test (count $picked) -gt 0
        command nvim $picked
    else
        command nvim
    end
end
