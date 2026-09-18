local mp = require("mp")

local LABELS = {
    no = "no",
    ["2"] = "once",
    inf = "infinite",
}

mp.add_key_binding("c", "cycle-playlist-loop", function()
    mp.command("no-osd cycle-values loop-playlist no 2 inf")
    local label = LABELS[tostring(mp.get_property("loop-playlist"))] or "??"
    mp.osd_message("playlist loop: " .. label, 2)
end)