-- Hyprland configuration; needs nothing outside this directory.
-- Load order matters: env before anything spawns, and execs last so the
-- session starts against a fully configured compositor.

HOME = os.getenv("HOME")

-- This file's own directory, not a fixed path, so a checkout elsewhere loads
-- its own modules. loadfile rather than `require` (which also resolves next to
-- the main config on 0.56) because load_module then names the failing module.
CONFIG = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]*$") or (HOME .. "/.config/hypr")

function file_exists(path)
    local f = io.open(path, "r")
    if f == nil then
        return false
    end
    io.close(f)
    return true
end

-- The first line of a sysfs or procfs file, or nil when it cannot be opened;
-- the modules read connector states, the lid and PCI vendors this way.
function read_first_line(path)
    local f = io.open(path, "r")
    if f == nil then
        return nil
    end
    local line = f:read("l")
    f:close()
    return line or ""
end

-- Names the failing module; otherwise a typo gives one opaque error.
function load_module(name)
    local path = CONFIG .. "/config/" .. name .. ".lua"
    if not file_exists(path) then
        error("config/" .. name .. ".lua is missing", 0)
    end

    local chunk, err = loadfile(path)
    if chunk == nil then
        error("config/" .. name .. ".lua: " .. tostring(err), 0)
    end

    local ok, runtime_err = pcall(chunk)
    if ok then
        return
    end

    -- Notify for a running session (no terminal); re-raise for --verify-config.
    pcall(function()
        hl.notification.create({
            text = "hypr: config/" .. name .. ".lua failed: " .. tostring(runtime_err),
            timeout = 15000,
        })
    end)
    error("config/" .. name .. ".lua: " .. tostring(runtime_err), 0)
end

load_module("env")
load_module("general")
-- After general (catch-all monitor rule), before keybinds (lid binds use it).
load_module("monitors")
load_module("rules")
load_module("keybinds")
load_module("execs")

-- Machine-local overrides; lives only in the installed config, never in the repo.
local override = CONFIG .. "/local.lua"
if file_exists(override) then
    local chunk = loadfile(override)
    if chunk ~= nil then
        pcall(chunk)
    end
end
