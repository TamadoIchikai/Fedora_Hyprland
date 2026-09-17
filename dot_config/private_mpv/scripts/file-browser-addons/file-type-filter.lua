-- file-type-filter.lua
-- mpv-file-browser addon: directory picker modes.
-- Control the mode with the script message:
--   script-message-to file_browser file-type-filter files|dirs|none
-- 'files': show files AND folders; ENTER on a folder navigates into it,
--          ENTER on a file still plays it — a picker for individual files.
-- 'dirs':  show only folders; ENTER on a folder loads it into the playlist.
-- Only browser ("browser" source) parses are filtered; playlist ("loadlist") scans
-- are left untouched so loading a folder still appends all of its files.

local mp = require 'mp'
local msg = require 'mp.msg'
local fb = require 'file-browser'

local mode = 'none'

mp.register_script_message('file-type-filter', function(new_mode)
    if new_mode == 'files' or new_mode == 'dirs' or new_mode == 'none' then
        mode = new_mode
        msg.verbose('file type filter mode set to: ' .. mode)
    else
        msg.warn('invalid file type filter mode: ' .. tostring(new_mode))
    end
end)

local parser = {
    api_version = '1.9',
    name = 'file-type-filter',
    priority = 10,
}

function parser:can_parse()
    return true
end

function parser:parse(directory, state)
    local list, opts = self:defer(directory, state)

    if list and state.source == 'browser' and mode == 'dirs' then
        local filtered = fb.copy_table(list)
        fb.filter(filtered)

        local shown = 0
        for i = #filtered, 1, -1 do
            if filtered[i].type ~= 'dir' then
                table.remove(filtered, i)
            else
                shown = shown + 1
            end
        end

        opts = opts or {}
        opts.filtered = true
        msg.verbose(("type filter '%s' on %q: %d item(s)"):format(mode, directory, shown))
        return filtered, opts
    end

    return list, opts
end

-- In 'files' mode plain ENTER on a folder should navigate into it instead of
-- adding it to the playlist. Returning false passes through to the default
-- ENTER behaviour (play file / load folder) in every other situation.
local function enter_handler(keybind, state, co)
    if mode ~= 'files' then return false end

    local item = state.list[state.selected]
    if not item or item.type ~= 'dir' then return false end

    mp.commandv('script-binding', 'file_browser/dynamic/down_dir')
    return true
end

parser.keybinds = {
    { 'ENTER', 'navigate_into_dir', enter_handler, {} },
}

return parser