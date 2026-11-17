function fif --description 'ripgrep + fzf: jump straight to a match in nvim'
    type -q rg; or begin; echo 'fif: ripgrep not installed' >&2; return 127; end
    type -q fzf; or begin; echo 'fif: fzf not installed' >&2; return 127; end

    set -l query $argv

    set -l match (rg \
        --line-number --column --no-heading --color=always \
        --smart-case --hidden --glob '!.git' --glob '!node_modules' \
        -- $query 2>/dev/null |
        fzf --ansi --delimiter=: \
            --preview 'bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null | head -80' \
            --preview-window 'right:60%' \
            --header '  rg › nvim')

    test -n "$match"; or return 0

    # "path:line:col:text" → path, line
    set -l parts (string split -m 2 -- : $match)
    set -l file $parts[1]
    set -l line $parts[2]

    if test -n "$line"
        command nvim +$line -- $file
    else
        command nvim -- $file
    end
end
