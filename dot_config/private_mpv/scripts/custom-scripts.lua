-- custom-scripts.lua
-- 1. Show active shaders (clean, one per line)
mp.register_script_message("show-shaders", function()
    local shaders = mp.get_property_native("glsl-shaders")
    if not shaders or #shaders == 0 then
        mp.osd_message("No shaders active", 3)
        return
    end
    local names = {}
    for _, path in ipairs(shaders) do
        names[#names + 1] = "• " .. (path:match("([^/\\]+)$") or path)
    end
    mp.osd_message(table.concat(names, "\n"), 5)
end)

-- 2. Smart Paste (strips Windows "Copy as path" quotes, trims, prevents crashes)
mp.register_script_message("smart-paste", function(mode)
    -- Refresh the property; required because clipboard-monitor defaults to no
    mp.commandv("update-clipboard", "text", "500")

    local text = mp.get_property("clipboard/text")
    if text then text = text:match("^%s*(.-)%s*$") end -- trim
    if not text or text == "" then
        mp.osd_message("Clipboard empty!")
        return
    end

    -- Safely strip a surrounding pair of double quotes
    if #text > 1 and text:sub(1, 1) == '"' and text:sub(-1) == '"' then
        text = text:sub(2, -2)
    end

    local append = (mode == "append")
    mp.commandv("loadfile", text, append and "append-play" or "replace")
    mp.osd_message(append and "Added to playlist" or "Playing from clipboard")
end)

-- 3. Open mpv-file-browser at $RESTIC_SOURCE_BASE/Musics
local function browse_musics(mode)
    local base = os.getenv("RESTIC_SOURCE_BASE")
    if not base or base == "" then
        mp.osd_message("RESTIC_SOURCE_BASE not set", 3)
        return
    end
    base = base:gsub("[/\\]+$", "")
    mp.commandv("script-message-to", "file_browser", "file-type-filter", mode)
    mp.commandv("script-message-to", "file_browser", "browse-directory", base .. "/Musics")
end

mp.register_script_message("browse-files", function() browse_musics("files") end)
mp.register_script_message("browse-musics", function() browse_musics("dirs") end)

-- 4. Toggle shuffle: shuffle everything and move the current song to the front,
--    press again to restore the order the playlist had before the shuffle.
local shuffled = false

-- mpv's unshuffle is one-shot and restores entries by the original_index they
-- were given during the last shuffle. Entries added or removed since then have
-- no such index, so the restore would only be partial. Drop the toggle state
-- instead, so the next press starts a fresh shuffle.
mp.observe_property("playlist-count", "number", function()
    shuffled = false
end)

mp.register_script_message("shuffle", function()
    if shuffled then
        mp.commandv("playlist-unshuffle")
        shuffled = false
        mp.osd_message("Playlist order restored")
        return
    end

    local playlist = mp.get_property_native("playlist")
    if not playlist or #playlist < 2 then
        mp.osd_message("Not enough songs to shuffle")
        return
    end

    -- id is unique per playlist entry, so it survives the shuffle. Matching on
    -- filename would break on duplicates in the playlist.
    local current_id
    for _, entry in ipairs(playlist) do
        if entry.current then
            current_id = entry.id
            break
        end
    end
    if not current_id then
        mp.osd_message("No current entry")
        return
    end

    mp.commandv("playlist-shuffle")

    -- playlist-move <a> <b> fills the slot vacated by index b, so the entry
    -- lands at b when a > b and at b - 1 when a < b. Moving towards index 0
    -- always wants b = 0.
    local target
    for i, entry in ipairs(mp.get_property_native("playlist") or {}) do
        if entry.id == current_id then
            target = i - 1
            break
        end
    end
    if target and target > 0 then
        mp.commandv("playlist-move", target, 0)
    end

    shuffled = true
    mp.osd_message("Playlist shuffled")
end)