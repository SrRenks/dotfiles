-- reddoted · yazi
--
-- One palette rule: black surfaces, white ink, grey for metadata, and red for
-- the single thing that is "live" (the current entry, an error, a deletion).
-- Colours are ANSI names, never hex, so yazi follows the terminal palette that
-- the Glyph shell rewrites on every wallpaper change.
--
-- Order matters: colour schemes and plugins are installed here, not in a
-- separate init fragment, because yazi loads exactly one init.lua.
--
-- Every plugin is wrapped in pcall: running `yazi` before `ya pkg install` must
-- still give a working file manager, not a crash.

-- ── linemode ────────────────────────────────────────────────────────────────
-- Size and time on the right of each row. Cheap: mtime comes from the same
-- stat() yazi already did, and size is only rendered for files.
function Linemode:size_and_mtime()
	local size = self._file:size()
	local time = math.floor(self._file.cha.mtime or 0)
	if time == 0 then
		time = ""
	elseif os.date("%Y", time) == os.date("%Y") then
		time = os.date("%b %d %H:%M", time)
	else
		time = os.date("%b %d  %Y", time)
	end
	return string.format("%s %s", size and ya.readable_size(size) or "-", time)
end

-- ── plugins ─────────────────────────────────────────────────────────────────

-- A full frame around all three panes; "rounded" matches the tmux popups.
pcall(function()
	require("full-border"):setup { set = "rounded" }
end)

-- Reports the working directory to the terminal (OSC 7), so "new tab here" and
-- "open here" in Ghostty land in the directory you are looking at.
pcall(function()
	require("term-cwd"):setup()
end)

-- MIME detection from an extension table instead of spawning file(1) for every
-- row. Falls back to file(1) for unknown extensions.
pcall(function()
	require("mime-ext"):setup { fallback_file1 = true }
end)

-- Git statuses in the linemode (needs the fetchers in yazi.toml).
pcall(function()
	require("git"):setup { order = 1500 }
end)
