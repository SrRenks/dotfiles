function yy --description 'Yazi picker: choose files and insert them into the command line'
    type -q yazi; or begin
        echo 'yy: yazi is not installed' >&2
        return 127
    end

    # --chooser-file is written when you open (Enter) a file, not when you quit.
    set -l tmp (mktemp)
    command yazi --chooser-file=$tmp
    set -l picked (cat $tmp 2>/dev/null)
    rm -f $tmp

    test -n "$picked"; or return 0

    # Absolute paths, escaped, one space between them, cursor at the end.
    set -l escaped (string escape -- $picked)
    commandline -it -- (string join ' ' $escaped)
    commandline -f repaint
end
