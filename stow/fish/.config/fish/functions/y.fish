function y --description 'Yazi here: browse, then cd to the directory you quit in'
    type -q yazi; or begin
        echo 'y: yazi is not installed' >&2
        return 127
    end

    # yazi writes its final cwd here; the file is the whole integration.
    set -l tmp (mktemp)
    command yazi --cwd-file=$tmp $argv
    set -l dir (cat $tmp 2>/dev/null)
    rm -f $tmp

    if test -n "$dir"; and test "$dir" != "$PWD"; and test -d "$dir"
        cd $dir
    end
end
