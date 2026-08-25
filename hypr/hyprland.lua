-- Hyprland configuration. Standalone: nothing outside this directory is
-- required, and no other dotfile project needs to be installed first.
--
-- Load order matters. Environment before anything that spawns a process,
-- settings before rules, rules before binds, and the shell last so it starts
-- against a configured compositor rather than a half-built one.

HOME = os.getenv("HOME")

-- The directory this file lives in, not a fixed path. `require` resolves
-- against ~/.config/hypr regardless of where the config actually is, so a
-- copy under a repository silently loaded nothing at all and still reported
-- "config ok". Locating ourselves and reading by absolute path removes that
-- whole class of failure, and makes `--verify-config` meaningful from any
-- checkout.
CONFIG = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]*$") or (HOME .. "/.config/hypr")

function file_exists(path)
    local f = io.open(path, "r")
    if f == nil then
        return false
    end
    io.close(f)
    return true
end

-- Runs a config module and names the broken one. Without this a typo in any
-- file produces one opaque error and no hint which file it came from.
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

    -- The notification is for a running session, where there is no terminal
    -- to read. The re-raise is for --verify-config, which is the only thing
    -- that catches a broken module before it is loaded for real.
    pcall(function()
        hl.notification.create({
            text = "hypr: config/" .. name .. ".lua failed: " .. tostring(runtime_err),
            duration = 15000,
        })
    end)
    error("config/" .. name .. ".lua: " .. tostring(runtime_err), 0)
end

load_module("env")
load_module("general")
load_module("rules")
load_module("keybinds")
load_module("execs")

-- A machine-specific file that never travels with the repository: monitor
-- pins, a work VPN bind, anything local.
local override = CONFIG .. "/local.lua"
if file_exists(override) then
    local chunk = loadfile(override)
    if chunk ~= nil then
        pcall(chunk)
    end
end
