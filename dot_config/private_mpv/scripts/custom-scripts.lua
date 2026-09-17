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