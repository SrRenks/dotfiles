function extract --description 'Extract almost anything into ./<basename>/'
    if test (count $argv) -eq 0
        echo 'usage: extract <archive> [more archives]' >&2
        return 1
    end

    for file in $argv
        if not test -f $file
            echo "extract: no such file: $file" >&2
            continue
        end

        # One directory per archive, never into the current one. Compound
        # suffixes go first so a.tar.gz lands in a/, not a.tar/.
        set -l dest (basename $file |
            string replace -r '\.(tar\.(gz|bz2|xz|zst|z)|tgz|taz|tbz2?|txz|tlz|AppImage)$' '' |
            string replace -r '\.[^.]*$' '')
        mkdir -p -- $dest

        switch $file
            case '*.tar.gz' '*.tgz' '*.tar.bz2' '*.tbz' '*.tar.xz' '*.txz' '*.tar.zst' '*.tar'
                tar -xf $file -C $dest
            case '*.zip' '*.7z' '*.rar' '*.gz' '*.xz' '*.zst' '*.bz2' '*.lz4' '*.z'
                # 7z handles all of them and is already a yazi dependency
                if type -q 7z
                    7z x -y -bso0 -bsp0 -o$dest -- $file
                else if type -q bsdtar
                    bsdtar -xf $file -C $dest
                else
                    echo 'extract: install 7zip or libarchive' >&2
                    return 127
                end
            case '*.deb'
                if type -q bsdtar
                    bsdtar -xf $file -C $dest
                else
                    ar x --output=$dest $file
                end
            case '*.rpm'
                rpm2cpio $file | cpio -idm -D $dest
            case '*.AppImage'
                # fish has no subshells: pushd/popd instead of ( cd && ... )
                set -l abs (realpath -- $file)
                chmod +x $abs
                pushd $dest >/dev/null
                $abs --appimage-extract >/dev/null
                popd >/dev/null
            case '*'
                echo "extract: unknown archive type: $file" >&2
                rmdir $dest 2>/dev/null
                continue
        end

        echo "extract: $file → $dest/"
    end
end
