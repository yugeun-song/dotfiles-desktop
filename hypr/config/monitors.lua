-- Output policy, run inside the compositor as hl.on handlers emitting
-- hl.monitor and hl.workspace_rule rules (no process, no polling):
--
--   external, lid open   -> panel and externals both on
--   external, lid shut   -> externals only, built-in panel off
--   no external output   -> built-in panel is the desktop
--
-- Workspaces follow the `workspaces` scheme (settings, or the override
-- file's "*" line the Displays panel writes): "dynamic" leaves them to
-- Hyprland, "panel-first" keeps 1 on the panel and 2..100 on the main
-- external, "blocks" also gives each further external ten of its own. The
-- main external is the preset's `main`, else the largest.
--
-- keep_internal = false in the settings turns the panel off beside an
-- external with the lid open too; a keep-internal marker file undoes that
-- without editing the settings.
--
-- Settings are a preset, not a description of one machine: monitor_settings
-- .lua (tracked) holds the values this desktop wants everywhere, and
-- monitor_settings.local.lua (untracked) the deviations of the machine at
-- hand, same fields, winning per field and per scale entry. What the preset
-- names but the machine lacks is inert (a scale entry for an absent panel
-- matches nothing); what the machine has but the preset does not name is
-- derived from what is detected: the scale from the output's pixel size and
-- kind (auto_scale), the mode from highrr, the panel from its connector
-- type. A bad or missing file is reported and ignored, and every default is
-- a working desktop. MONITORS.describe() prints where each value came from.
--
-- Overrides. On top of that policy sits OVERRIDES_FILE, written by
-- scripts/monitor-override.sh (the bar's display panel calls it): per output,
-- enabled, mode, scale, transform, and for the panel its side of the first
-- external and whether it mirrors. The file is re-read at load and when the
-- script asks (MONITORS.reload_overrides), never on the event path. An
-- override narrows what the policy does; it cannot leave the desktop dark:
--   - the panel off only counts while a desired external is lit, exactly as
--     keep_internal = false does, and the lid still wins over enabled = true;
--   - an external off is suspended while the lid is shut, so the shut laptop
--     is never left with every screen off;
--   - a mode the output does not list falls back to highrr with one warning;
--   - every disabling is stage two (see below), and it is skipped if nothing
--     would stay lit.
-- Every override is also honoured before an output lights (a rule for an
-- absent output waits for it), so a display overridden off stays off when
-- it is plugged in.
--
-- Facts from the Hyprland 0.56.2 sources that shape the code:
--
--   FALLBACK    When the last output goes, the compositor creates a headless
--               output named FALLBACK that shows up like a real screen. Counted
--               as external it kept the panel off (black screen on unplug), so
--               FALLBACK and HEADLESS-* are ignored.
--
--   reload      hyprctl reload drops all monitor and workspace rules and all
--               timers, re-runs this file, then re-checks outputs. So the
--               policy also runs at load (a docked reload leaves each screen
--               as it was, without blinking) and the verify timer is re-armed
--               there.
--
--   idempotent  A rule matching current state costs nothing, so each
--               evaluation emits the full desired state; no bookkeeping.
--               Two fields do not default when left out: a rule without
--               mirror keeps an earlier mirror, and transform likewise, so
--               every enabling rule names both.
--
--   invisible   hl.get_monitors() and hl.get_monitor() see enabled outputs
--               only: a disabled output and a mirroring one both read as
--               absent. Names come from sysfs and STATE_FILE instead, and a
--               mirroring panel is treated as holding no workspaces.
--
--   workspaces  A workspace rule binds a workspace to an output by name.
--               Hyprland opens a bound workspace on its output, and when an
--               output connects it takes its default = true workspace, then
--               every bound workspace is moved home. That move is queued
--               behind the monitor.added event, so rules emitted from the
--               event already count. A rule naming an output that is absent
--               or disabled places nothing, so the rules stand in every
--               state.
--
--   lid         libinput, not Hyprland, reports a lid that is already shut,
--               and only when it adds the switch at compositor start. A
--               reload re-runs this file without that event, so the state at
--               load comes from ACPI.
--
-- hl.get_monitors() lists enabled outputs only, so the panel name comes from
-- sysfs and its description (for scale matching) from STATE_FILE.
--
-- Limits: verify counts enabled outputs, not visible ones; an enabled but
-- dark external keeps a panel that is due off (lid shut, keep_internal =
-- false, overridden off) off (use ~/recover-desktop from a console).
-- A wlr-output-management client (wlr-randr, wdisplays, kanshi) overrides
-- every rule for the session unseen; do not run one alongside this.
--
-- Callbacks must fit the 50 ms budget: nothing spawns, and the only file I/O
-- on the event path is one open of the keep-internal marker (the lid's ACPI
-- state is read at load and on resume only; the overrides at load and on
-- request only).
--
-- Manual run: hyprctl eval 'MONITORS.evaluate("manual")'
--             hyprctl eval 'MONITORS.reload_overrides("manual")'

local M = {}
MONITORS = M

-- print() is invisible unless debug:disable_logs is off, so anything needing
-- action also goes on screen.
local function warn(message)
    print("monitors: " .. message)
    pcall(function()
        hl.notification.create({ text = "monitors: " .. message, timeout = 10000 })
    end)
end

local SETTINGS_FILE = CONFIG .. "/monitor_settings.lua"
-- Untracked, read after the preset; the same fields, merged over it.
local LOCAL_SETTINGS_FILE = CONFIG .. "/monitor_settings.local.lua"
local KEEP_INTERNAL_FILE = CONFIG .. "/keep-internal"
local STATE_DIR = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/hypr"
local STATE_FILE = STATE_DIR .. "/monitors.state"
-- Written by scripts/monitor-override.sh; the format is documented there.
local OVERRIDES_FILE = STATE_DIR .. "/monitor-overrides"

-- Defaults. Connector type decides internal vs external. Removal settles
-- fast (the desktop is dark until the panel returns); arrival settles long
-- (both screens on is harmless, a training link may flap). settle_max_ms
-- forces an evaluation during endless flapping.
-- settle_synthetic_ms, panel_off_*, sysfs and acpi_lid are not settable from
-- the settings file (see load_settings).
local policy = {
    internal = { "^eDP", "^LVDS", "^DSI" },
    synthetic = { "^FALLBACK$", "^HEADLESS%-" },
    scales = {},
    -- For outputs no scales entry names: the logical width to aim for, per
    -- kind (see M.auto_scale). false means scale 1 for them.
    auto_scale = { internal = 1920, external = 2560 },
    -- The external that takes 0x0 and the workspaces when several are lit: a
    -- description prefix, matched like a scales entry. nil: the largest
    -- logical area, then name order.
    main = nil,
    -- How workspaces are spread over the outputs: "dynamic" is Hyprland's own
    -- behaviour (nothing bound), "panel-first" is this desktop's preset
    -- (1 on the panel, 2..LAST_WORKSPACE on the main external), "blocks" gives
    -- each further external ten of its own (11-20, 21-30). The override file
    -- can replace it (the Displays panel writes that line).
    workspaces = "dynamic",
    keep_internal = true,
    settle_removed_ms = 400,
    settle_added_ms = 2000,
    -- FALLBACK means no screen is left; waiting cannot help. Just long
    -- enough to leave the event handler.
    settle_synthetic_ms = 60,
    settle_max_ms = 6000,
    verify_ms = 3000,
    verify_limit = 5,
    sysfs = true,
    -- Where the lid's state is read at load; false skips it (lid open).
    acpi_lid = "/proc/acpi/button/lid",
    -- Gap between lighting outputs and darkening the ones due off, so the two
    -- modesets never reach the driver as one commit (see M.evaluate).
    panel_off_delay_ms = 700,
    -- Sooner check after an off stage, the one action that can remove the
    -- last screen.
    panel_off_verify_ms = 900,
}

local function is_string_list(value)
    if type(value) ~= "table" then
        return false
    end
    for _, item in ipairs(value) do
        if type(item) ~= "string" then
            return false
        end
    end
    return true
end

-- Per-field validation: one bad value falls back alone, with a warning.
-- Called for the preset, then for the local file, whose fields win; its
-- scale entries go in front so they match first.
local function load_settings(path, local_file)
    local chunk, err = loadfile(path)
    if not chunk then
        local f = io.open(path, "r")
        if f then
            f:close()
            warn(path .. " could not be loaded, using defaults: " .. tostring(err))
        end
        return
    end
    local ok, settings = pcall(chunk)
    if not ok then
        warn(path .. " failed to run, using defaults: " .. tostring(settings))
        return
    end
    if type(settings) ~= "table" then
        warn(path .. " must return a table, using defaults")
        return
    end

    local function take(key, check, describe)
        local value = settings[key]
        if value == nil then
            return
        end
        if check(value) then
            policy[key] = value
        else
            warn(string.format("%s: %s must be %s, using the default", path, key, describe))
        end
    end
    local function positive(value)
        return type(value) == "number" and value > 0
    end
    -- A bad pattern would raise in string.find at load, which fails the whole
    -- config (no binds). Test-compile each one first.
    local function is_pattern_list(value)
        if not is_string_list(value) or #value == 0 then
            return false
        end
        for _, pattern in ipairs(value) do
            if not pcall(string.find, "", pattern) then
                return false
            end
        end
        return true
    end
    take("internal", is_pattern_list, "a non-empty list of valid Lua patterns")
    take("synthetic", is_pattern_list, "a non-empty list of valid Lua patterns")
    take("keep_internal", function(v) return type(v) == "boolean" end, "true or false")
    take("settle_removed_ms", positive, "a number of milliseconds")
    take("settle_added_ms", positive, "a number of milliseconds")
    take("settle_max_ms", positive, "a number of milliseconds")
    take("verify_ms", positive, "a number of milliseconds")
    take("verify_limit", positive, "a number")
    take("auto_scale", function(v)
        return v == false or (type(v) == "table" and positive(v.internal) and positive(v.external))
    end, "false or { internal = <logical width>, external = <logical width> }")
    take("main", function(v) return type(v) == "string" and v ~= "" end, "a description prefix")
    take("workspaces", function(v)
        return v == "dynamic" or v == "panel-first" or v == "blocks"
    end, "\"dynamic\", \"panel-first\" or \"blocks\"")
    if type(policy.main) == "string" then
        policy.main = policy.main:gsub(",", "")
    end

    if settings.scales ~= nil then
        local scales = settings.scales
        -- One entry written without the surrounding list is the obvious slip.
        if type(scales) == "table" and (scales.match ~= nil or scales.output ~= nil) then
            scales = { scales }
        end
        if type(scales) ~= "table" then
            warn(path .. ": scales must be a list, using the default")
        else
            local here = {}
            for i, entry in ipairs(scales) do
                -- Type test first: indexing a non-table raises at load.
                local scale = type(entry) == "table" and tonumber(entry.scale) or nil
                local match = type(entry) == "table" and entry.match or nil
                local output = type(entry) == "table" and entry.output or nil
                if type(entry) ~= "table" or not scale or scale <= 0
                    or (match == nil and output == nil)
                    or (match ~= nil and type(match) ~= "string")
                    or (output ~= nil and type(output) ~= "string") then
                    warn(string.format("%s: scales[%d] needs match or output, and a positive scale; ignored", path, i))
                else
                    here[#here + 1] = {
                        match = match and (match:gsub(",", "")) or nil,
                        output = output,
                        scale = scale,
                    }
                end
            end
            if local_file then
                for i = #here, 1, -1 do
                    table.insert(policy.scales, 1, here[i])
                end
            else
                for _, entry in ipairs(here) do
                    policy.scales[#policy.scales + 1] = entry
                end
            end
        end
    end
end

load_settings(SETTINGS_FILE, false)
load_settings(LOCAL_SETTINGS_FILE, true)

-- Set by scripts/monitors-selftest.sh (nested compositor: WAYLAND-1 is the
-- panel, HEADLESS-* the externals). Wins over the settings file.
if type(MONITOR_POLICY_OVERRIDE) == "table" then
    for key, value in pairs(MONITOR_POLICY_OVERRIDE) do
        policy[key] = value
    end
end

-- Every id the binds reach is bound, not only 2..10: an unbound workspace
-- opens on the focused output, which may be the panel. One rule per id: a
-- range selector (r[2-100]) is honoured for existing workspaces but not for
-- one being created, so a range could not keep a new workspace off the
-- panel; 100 rules cost nothing measurable, more only buys ids nobody
-- reaches. Exported: config/keybinds.lua clamps its workspace walk to it.
local LAST_WORKSPACE = 100
M.LAST_WORKSPACE = LAST_WORKSPACE

local function matches(name, patterns)
    for _, pattern in ipairs(patterns) do
        if name:find(pattern) then
            return true
        end
    end
    return false
end

local function classify(name)
    if matches(name, policy.synthetic) then
        return "synthetic"
    end
    if matches(name, policy.internal) then
        return "internal"
    end
    return "external"
end

local function read_lines(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

-- Descriptions are compared with commas dropped and edges trimmed, the form
-- the preset's `match`, the override selectors and the Displays panel all
-- use; the raw string from Hyprland keeps its commas.
local function normalize_description(description)
    return (tostring(description or ""):gsub(",", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sorted_keys(set)
    local names = {}
    for name in pairs(set) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- The description is "make model serial" without commas; match is a prefix
-- ending at a word boundary. Returns the entry, or nil for an unlisted output.
local function scale_entry(name, description)
    for _, entry in ipairs(policy.scales) do
        if entry.output and entry.output == name then
            return entry
        end
        if entry.match and description and description ~= "" then
            if description == entry.match or description:sub(1, #entry.match + 1) == entry.match .. " " then
                return entry
            end
        end
    end
    return nil
end

-- The scale for an output no entry names, from its pixel size alone: the
-- step, among those that keep both logical dimensions integral (Hyprland
-- corrects any other with a notification), whose logical width is nearest
-- the target for its kind. Physical size is not used: EDIDs lie about it,
-- and the targets already encode how far each kind of screen is read from.
-- Ties fall to the smaller step, the crisper one.
local SCALE_STEPS = { 1, 1.25, 1.5, 1.75, 2, 2.5, 3 }

-- targets defaults to the settings' auto_scale; passed explicitly by the
-- selftest, which runs with the automatic choice switched off.
function M.auto_scale(width, height, class, targets)
    targets = targets or policy.auto_scale
    if not targets or not width or not height or width <= 0 or height <= 0 then
        return 1
    end
    local target = class == "internal" and targets.internal or targets.external
    local best, best_diff = 1, math.huge
    for _, step in ipairs(SCALE_STEPS) do
        local lw, lh = width / step, height / step
        if math.abs(lw - math.floor(lw + 0.5)) < 1e-6 and math.abs(lh - math.floor(lh + 0.5)) < 1e-6 then
            local diff = math.abs(lw - target)
            if diff < best_diff then
                best, best_diff = step, diff
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- What outputs exist, whether or not the compositor has one enabled.
-- ---------------------------------------------------------------------------
-- known: name -> description of every real output seen, and sizes: name ->
-- { width, height } of its last mode. A disabled output's description and
-- size cannot be queried, so both persist in STATE_FILE (one line per
-- output: name, description, width, height; the size fields are absent in
-- files written before auto_scale existed). Stale entries only yield rules
-- for outputs that never appear, which is harmless.
local known = {}
local sizes = {}

local function load_state()
    local lines = read_lines(STATE_FILE)
    if not lines then
        return
    end
    for _, line in ipairs(lines) do
        local name, rest = line:match("^([^\t]+)\t(.*)$")
        if name then
            local description, w, h = rest:match("^(.-)\t(%d+)\t(%d+)$")
            if description then
                known[name] = normalize_description(description)
                sizes[name] = { tonumber(w), tonumber(h) }
            else
                known[name] = normalize_description(rest)
            end
        end
    end
end

-- Atomic write (temp + rename), since the next launch may follow a crash.
-- From its own timer so a stalled disk cannot delay verify. Warned once:
-- otherwise the only symptom is scale 1 after a docked boot.
local state_dirty = false
local state_write_failed = false

local function save_state()
    state_dirty = false
    local tmp = STATE_FILE .. ".new"
    local f = io.open(tmp, "w")
    if not f then
        if not state_write_failed then
            warn("cannot write " .. STATE_FILE .. "; a panel disabled at boot will come up at scale 1 until it is seen")
            state_write_failed = true
        end
        return
    end
    local names = {}
    for name in pairs(known) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local size = sizes[name]
        if size then
            f:write(name, "\t", known[name], "\t", size[1], "\t", size[2], "\n")
        else
            f:write(name, "\t", known[name], "\n")
        end
    end
    f:close()
    os.rename(tmp, STATE_FILE)
end

local function schedule_state_save()
    if state_dirty then
        return
    end
    state_dirty = true
    hl.timer(save_state, { timeout = 1000, type = "oneshot" })
end

local function note(name, description)
    if classify(name) == "synthetic" then
        return
    end
    description = normalize_description(description)
    if description == "" and known[name] ~= nil then
        return
    end
    if known[name] == description then
        return
    end
    known[name] = description
    schedule_state_save()
end

-- The pixel size is what auto_scale needs before the output is lit again.
local function note_size(name, width, height)
    local size = sizes[name]
    if size and size[1] == width and size[2] == height then
        return
    end
    sizes[name] = { width, height }
    schedule_state_save()
end

-- Probed by name: listing a directory would need a process. DRM type names.
local CONNECTOR_TYPES = {
    "eDP", "LVDS", "DSI", "HDMI-A", "HDMI-B", "DP", "DVI-I", "DVI-D", "DVI-A", "VGA", "DPI", "USB", "Virtual",
}

local function sysfs_connectors()
    local found = {}
    for card = 0, 1 do
        for _, ctype in ipairs(CONNECTOR_TYPES) do
            for index = 1, 6 do
                local name = ctype .. "-" .. index
                local status = read_first_line(string.format("/sys/class/drm/card%d-%s/status", card, name))
                if status then
                    found[name] = (status == "connected")
                end
            end
        end
    end
    return found
end

-- The outputs the compositor has enabled right now, split by the rule.
local function present()
    local state = { external = {}, internal = {}, real = 0 }
    for _, monitor in ipairs(hl.get_monitors()) do
        local name = monitor.name
        if name then
            local class = classify(name)
            if class ~= "synthetic" then
                note(name, monitor.description or "")
                -- Zero size = enabled but undrivable (every mode refused, dock
                -- over bandwidth). Counting it would keep the panel off on a
                -- black screen that verify cannot see, so it is not real.
                if (monitor.width or 0) > 0 and (monitor.height or 0) > 0 then
                    note_size(name, monitor.width, monitor.height)
                    state.real = state.real + 1
                    if class == "internal" then
                        state.internal[#state.internal + 1] = name
                    else
                        state.external[#state.external + 1] = name
                    end
                end
            end
        end
    end
    table.sort(state.external)
    table.sort(state.internal)
    return state
end

-- ---------------------------------------------------------------------------
-- Overrides: what the display panel, or a hand-edited file, asked for.
-- ---------------------------------------------------------------------------
-- One line per override, <selector> TAB <field> TAB <value>; the selector is
-- the output's description (so the override follows the display across
-- connectors) or "name:" plus the connector. Parsed once here; a line that
-- does not parse is dropped with a warning and the rest still count, since
-- the script validates before writing and a hand edit should not undo every
-- other override.
local by_description = {}
local by_name = {}
-- Lines whose selector is "*": settings for the desk rather than an output
-- (workspaces so far).
local global_override = {}

-- "auto" means the field is absent: the policy decides.
local function parse_override(field, value)
    if field == "enabled" or field == "mirror" then
        if value == "true" then
            return true
        end
        if value == "false" then
            return false
        end
        return nil, "true or false"
    elseif field == "mode" then
        if value == "auto" then
            return "auto"
        end
        local w, h, r = value:match("^(%d+)x(%d+)@(%d+%.?%d*)$")
        if not w then
            return nil, "WxH@R or auto"
        end
        return { width = tonumber(w), height = tonumber(h), refresh = tonumber(r), text = value }
    elseif field == "scale" then
        if value == "auto" then
            return "auto"
        end
        local n = tonumber(value)
        if not n or n < 0.5 or n > 3 then
            return nil, "a number from 0.5 to 3, or auto"
        end
        return n
    elseif field == "transform" then
        if value == "auto" then
            return "auto"
        end
        local n = tonumber(value)
        if not n or n ~= math.floor(n) or n < 0 or n > 7 then
            return nil, "an integer from 0 to 7, or auto"
        end
        return n
    elseif field == "side" then
        if value == "left" or value == "right" or value == "above" or value == "below" then
            return value
        end
        return nil, "left, right, above or below"
    elseif field == "workspaces" then
        if value == "dynamic" or value == "panel-first" or value == "blocks" then
            return value
        end
        if value == "auto" then
            return "auto"
        end
        return nil, "dynamic, panel-first, blocks or auto"
    end
    return nil, "a known field (enabled, mode, scale, transform, side, mirror, workspaces)"
end

local function load_overrides()
    by_description = {}
    by_name = {}
    global_override = {}
    local lines = read_lines(OVERRIDES_FILE)
    if not lines then
        return
    end
    local bad = {}
    for i, line in ipairs(lines) do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local selector, field, value = line:match("^([^\t]+)\t([^\t]+)\t([^\t]*)$")
            if not selector then
                bad[#bad + 1] = string.format("line %d is not <output><TAB><field><TAB><value>", i)
            else
                local parsed, expected = parse_override(field, value)
                if parsed == nil then
                    bad[#bad + 1] = string.format("line %d: %s must be %s", i, field, expected)
                elseif (selector == "*") ~= (field == "workspaces") then
                    bad[#bad + 1] = string.format("line %d: %s goes with the selector %s", i, field,
                        field == "workspaces" and "*" or "of an output")
                elseif parsed ~= "auto" then
                    if selector == "*" then
                        global_override[field] = parsed
                    else
                        local bucket, key = by_description, selector
                        local name = selector:match("^name:(.+)$")
                        if name then
                            bucket, key = by_name, name
                        end
                        bucket[key] = bucket[key] or {}
                        bucket[key][field] = parsed
                    end
                end
            end
        end
    end
    -- One notification however many lines are wrong.
    if #bad > 0 then
        local more = #bad > 1 and string.format(" (and %d more)", #bad - 1) or ""
        warn(OVERRIDES_FILE .. ": " .. bad[1] .. more .. "; ignored")
    end
end

local NO_OVERRIDE = {}

-- The description entry wins field by field over the name entry.
local function override_for(name)
    local description = known[name]
    local a = description and description ~= "" and by_description[description] or nil
    local b = by_name[name]
    if not a and not b then
        return NO_OVERRIDE
    end
    if not b then
        return a
    end
    if not a then
        return b
    end
    local merged = {}
    for key, value in pairs(b) do
        merged[key] = value
    end
    for key, value in pairs(a) do
        merged[key] = value
    end
    return merged
end

-- Refresh rates are compared to the two decimals the file carries; Hyprland
-- prints the same two and matches loosely itself.
local function offers_mode(monitor, mode)
    local modes = monitor.available_modes
    if type(modes) ~= "table" then
        return true
    end
    for _, m in ipairs(modes) do
        if type(m) == "table" and m.width == mode.width and m.height == mode.height
            and math.abs((m.refresh_rate or 0) - mode.refresh) < 0.01 then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The desired state, as rules.
-- ---------------------------------------------------------------------------
-- highrr matches the catch-all in general.lua, so it costs nothing. mirror
-- and transform are always named (see idempotent above). A mode that the
-- output does not offer is refused here, while it can still be checked; a
-- disabled output's list cannot be read, and Hyprland then falls back on its
-- own.
-- The preset entry if one names the output, else the automatic choice from
-- its pixel size (live, or the size on record while it is off), else 1 for
-- an output never lit yet: the rule that lights it is corrected on its
-- monitor.added, a relayout and not a modeset.
local function scale_for(name)
    local entry = scale_entry(name, known[name])
    if entry then
        return entry.scale
    end
    if not policy.auto_scale then
        return 1
    end
    local monitor = hl.get_monitor(name)
    local width = monitor and monitor.width or 0
    local height = monitor and monitor.height or 0
    if width <= 0 or height <= 0 then
        local size = sizes[name]
        if not size then
            return 1
        end
        width, height = size[1], size[2]
    end
    return M.auto_scale(width, height, classify(name))
end

local mode_warned = {}

local function enabled_rule(name, position, mirror_of)
    local override = override_for(name)
    local mode = "highrr"
    if override.mode then
        local monitor = hl.get_monitor(name)
        if monitor and not offers_mode(monitor, override.mode) then
            if not mode_warned[name .. " " .. override.mode.text] then
                mode_warned[name .. " " .. override.mode.text] = true
                warn(name .. " does not offer " .. override.mode.text .. "; using its highest refresh rate")
            end
        else
            mode = override.mode.text
        end
    end
    return {
        output = name,
        disabled = false,
        mode = mode,
        position = position,
        scale = override.scale or scale_for(name),
        transform = override.transform or 0,
        mirror = mirror_of or "",
    }
end

-- One line per known output saying where its scale comes from: the
-- override, a preset entry, the automatic choice, or the default 1 with why.
-- Read with: hyprctl repl 'return MONITORS.describe()'
function M.describe()
    local lines = {}
    for _, name in ipairs(sorted_keys(known)) do
        local override = override_for(name)
        local entry = scale_entry(name, known[name])
        local size = sizes[name]
        local monitor = hl.get_monitor(name)
        local source
        if override.scale then
            source = string.format("scale %s from the override file", override.scale)
        elseif entry then
            source = string.format("scale %s from the preset entry %s", entry.scale,
                entry.output and ("output " .. entry.output) or ("match " .. entry.match))
        elseif not policy.auto_scale then
            source = "scale 1 (auto_scale is off)"
        elseif size then
            source = string.format("scale %s automatic for %dx%d as %s", M.auto_scale(size[1], size[2], classify(name)),
                size[1], size[2], classify(name))
        else
            source = "scale 1 (never lit, no size on record yet)"
        end
        lines[#lines + 1] = string.format("%s%s [%s]: %s", name, monitor and "" or " (not lit)", known[name], source)
    end
    lines[#lines + 1] = M.status()
    return table.concat(lines, "\n")
end

local function keep_internal()
    return policy.keep_internal or file_exists(KEEP_INTERNAL_FILE)
end

-- Set by the lid binds, and at load from ACPI (see lid above).
local lid_closed = false

-- Set by M.prepare_exit() while the session is about to end (see Session end
-- below): the panel beside a lit external goes off as with the lid shut.
local exiting = false

-- Connector states read at load (see plan).
local sysfs = {}

-- Once per set of overrides: the panel asked off with no external left to
-- show anything is a state the policy refuses, and silently would look like
-- an override that does not work.
local kept_warned = false

-- The main external first: the preset's `main` if it names a lit one, else
-- the largest logical area, then name order (the list arrives sorted).
-- Returns why, for describe().
-- Width and height in logical pixels for a lit output, or nil. `planned`
-- takes the values the current evaluation asks for (an override's mode and
-- scale, or the automatic scale) instead of what the output shows now, which
-- lags a rule by a frame.
local function logical_size(name, planned)
    local monitor = hl.get_monitor(name)
    if not monitor then
        return nil
    end
    local width, height = monitor.width or 0, monitor.height or 0
    local scale = monitor.scale
    if planned then
        local override = override_for(name)
        if override.mode and offers_mode(monitor, override.mode) then
            width, height = override.mode.width, override.mode.height
        end
        scale = override.scale or scale_for(name)
    end
    if not scale or scale <= 0 then
        scale = 1
    end
    if width <= 0 or height <= 0 then
        return nil
    end
    return width / scale, height / scale
end

local function logical_area(name)
    local width, height = logical_size(name, false)
    if not width then
        return 0
    end
    return width * height
end

local function order_externals(list)
    if #list == 0 then
        return "none"
    end
    if #list == 1 then
        return "the only one"
    end
    local main, reason
    if policy.main then
        for _, name in ipairs(list) do
            local description = known[name] or ""
            if description == policy.main or description:sub(1, #policy.main + 1) == policy.main .. " " then
                main, reason = name, "the preset's main"
                break
            end
        end
    end
    if not main then
        local best = -1
        for _, name in ipairs(list) do
            local area = logical_area(name)
            if area > best then
                best, main, reason = area, name, "the largest logical area"
            end
        end
        if best <= 0 then
            reason = "the first by name"
        end
    end
    for i, name in ipairs(list) do
        if name == main and i > 1 then
            table.remove(list, i)
            table.insert(list, 1, name)
            break
        end
    end
    return reason
end

-- The workspace rules a scheme wants, as { workspace, monitor, default }:
--   dynamic      none: Hyprland opens each workspace where it is asked for
--   panel-first  1 on the panel (its default), 2..LAST_WORKSPACE on the main
--                external
--   blocks       as panel-first, but the k-th further external takes
--                10k+1..10k+10 with its first id as default; the main keeps
--                the rest
-- Only lit desired externals are named; a rule naming an absent output
-- places nothing, so the panel keeps everything while alone.
local function bindings_for(p)
    local list = {}
    if p.ws_scheme == "dynamic" then
        return list
    end
    if p.ws_panel then
        list[#list + 1] = { workspace = "1", monitor = p.ws_panel, default = true }
    end
    local main = p.ws_external
    if not main then
        return list
    end
    local owner, first_of_block = {}, {}
    if p.ws_scheme == "blocks" then
        for k = 2, #p.externals do
            local first = 10 * (k - 1) + 1
            for id = first, first + 9 do
                owner[id] = p.externals[k]
            end
            first_of_block[first] = true
        end
    end
    for id = 2, LAST_WORKSPACE do
        list[#list + 1] = { workspace = tostring(id), monitor = owner[id] or main, default = first_of_block[id] or nil }
    end
    return list
end

-- The whole desired state for one evaluation, from what is lit now, what is
-- known, the lid and the overrides:
--   externals   desired-on externals that are lit now, sorted; the first
--               takes 0x0 and the workspaces
--   on          every output due an enabling rule (lit or not)
--   off         every output due a disabled rule (lit or not)
--   pending     the subset of off that is lit now, i.e. needs a modeset
--   mirror      the external the panel mirrors, if any
-- The panel off only counts beside a lit desired external, as with
-- keep_internal = false, so the desired set cannot be empty by construction;
-- an external off is suspended while the lid is shut for the same reason.
-- quiet: a read-only caller (status, describe), which must not raise the
-- warning below.
local function plan(state, at_load, quiet)
    local p = { externals = {}, on = {}, off = {}, off_set = {}, pending = {}, side = "right" }
    local lit = {}
    for _, name in ipairs(state.internal) do
        lit[name] = true
    end
    for _, name in ipairs(state.external) do
        lit[name] = true
    end

    -- Externals: the lit ones, plus every known one so a rule can re-light
    -- what an override turned off, and keep off what is not plugged in yet.
    local candidates = {}
    for _, name in ipairs(state.external) do
        candidates[name] = true
    end
    for name in pairs(known) do
        if classify(name) == "external" then
            candidates[name] = true
        end
    end
    -- Connected at load but never seen (a fresh or lost state file): the
    -- sysfs branch below must count it too, or a docked first boot lights
    -- the panel it is meant to keep dark.
    for name, connected in pairs(sysfs) do
        if connected and classify(name) == "external" then
            candidates[name] = true
        end
    end
    local wants_on = {}
    for _, name in ipairs(sorted_keys(candidates)) do
        if override_for(name).enabled == false and not lid_closed then
            p.off[#p.off + 1] = name
            p.off_set[name] = true
        else
            wants_on[name] = true
            p.on[#p.on + 1] = name
        end
    end
    for _, name in ipairs(state.external) do
        if wants_on[name] then
            p.externals[#p.externals + 1] = name
        end
    end
    p.main_reason = order_externals(p.externals)

    -- sysfs counts only at first launch (no output, no workspace), so a
    -- docked boot that keeps the panel off never lights it. Later,
    -- "connected" does not prove a working screen; only the compositor's
    -- list decides.
    local externals_present = #p.externals > 0
    if at_load and state.real == 0 and #hl.get_monitors() == 0 and #hl.get_workspaces() == 0 then
        for name, connected in pairs(sysfs) do
            if connected and classify(name) == "external" and wants_on[name] then
                externals_present = true
                p.sysfs_only = true
            end
        end
    end

    -- The panel. Beside a lit external it goes off with the lid shut, where
    -- it would hold workspace 1 out of sight, when keep_internal is off
    -- (enabled = true undoes that, the lid it cannot), when overridden off,
    -- or while the session ends (prepare_exit, which enabled = true cannot
    -- undo either).
    local internals = {}
    for name in pairs(known) do
        if classify(name) == "internal" then
            internals[name] = true
        end
    end
    for _, name in ipairs(sorted_keys(internals)) do
        local override = override_for(name)
        local off = externals_present and (lid_closed or exiting or override.enabled == false
            or (not keep_internal() and override.enabled ~= true))
        if override.enabled == false and not externals_present and #p.off > 0 and not kept_warned and not quiet then
            kept_warned = true
            warn("the panel stays on: every external is off")
        end
        if off then
            p.off[#p.off + 1] = name
            p.off_set[name] = true
        else
            p.on[#p.on + 1] = name
            -- The first panel by name decides the layout; a second internal
            -- output is a curiosity that keeps automatic placement.
            if not p.first_internal then
                p.first_internal = name
                if override.side then
                    p.side = override.side
                end
                if override.mirror and p.externals[1] then
                    p.mirror = p.externals[1]
                end
            end
        end
    end

    for _, name in ipairs(p.off) do
        if lit[name] then
            p.pending[#p.pending + 1] = name
        end
    end

    -- Workspaces, per scheme (bindings_for). The panel that holds 1 is the
    -- lit one, else the connected or last seen one.
    p.ws_external = p.externals[1]
    local panel = state.internal[1]
    if not panel then
        -- The connected or last seen one: default = true only counts if the
        -- rule stands before the panel lights.
        local names = {}
        for name in pairs(internals) do
            if sysfs[name] ~= false then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        panel = names[1]
    end
    -- A mirroring panel holds none: 1 goes to the external it mirrors.
    p.ws_panel = p.mirror and p.ws_external or panel
    p.ws_scheme = global_override.workspaces or policy.workspaces
    p.bindings = bindings_for(p)
    -- Both lit, nothing due off, the panel its own screen: the moment to put
    -- stray workspaces back (see place_workspaces).
    if p.ws_scheme ~= "dynamic" and #p.pending == 0 and state.internal[1] and not p.mirror and p.ws_external then
        p.place_panel = state.internal[1]
    end
    return p
end

-- Lighting is safe in any order; darkening is not. Turning the panel off
-- frees a CRTC, and batched with an external's enable the two modesets
-- become one commit through a no-output state, where the compositor once
-- stayed wedged. So everything due off goes off separately, second.

-- Enabling rules only. An output due off gets no rule at all, so its last
-- rule stands and it does not blink on between stages or on reload. The
-- first external is pinned at 0x0 (the bar treats the leftmost screen as
-- main) unless the panel is put on its left.
local function lit_rules(p)
    local rules = {}
    for _, name in ipairs(p.on) do
        local position = "auto"
        if classify(name) == "internal" then
            if name == p.first_internal then
                if p.side == "left" then
                    position = "0x0"
                elseif p.side == "above" then
                    position = "auto-up"
                elseif p.side == "below" then
                    position = "auto-down"
                end
            end
            rules[#rules + 1] = enabled_rule(name, position, name == p.first_internal and p.mirror or nil)
        else
            if name == p.externals[1] then
                position = p.side == "left" and "auto-right" or "0x0"
            end
            rules[#rules + 1] = enabled_rule(name, position, nil)
        end
    end
    return rules
end

local function off_rules(p)
    local rules = {}
    for _, name in ipairs(p.off) do
        rules[#rules + 1] = { output = name, disabled = true }
    end
    return rules
end

-- Per stage, so each stage only prints on its own changes.
local last_summary = {}

local function apply(rules, reason, stage)
    local parts = {}
    for _, rule in ipairs(rules) do
        hl.monitor(rule)
        if rule.disabled then
            parts[#parts + 1] = rule.output .. ":off"
        else
            local part = string.format("%s:%s/%s/x%s", rule.output, rule.mode, rule.position, rule.scale)
            if rule.transform ~= 0 then
                part = part .. "/t" .. rule.transform
            end
            if rule.mirror ~= "" then
                part = part .. "/mirror=" .. rule.mirror
            end
            parts[#parts + 1] = part
        end
    end
    local summary = table.concat(parts, " ")
    if summary ~= last_summary[stage] then
        print(string.format("monitors: %s -> %s", reason, summary))
        last_summary[stage] = summary
    end
end

-- ---------------------------------------------------------------------------
-- Evaluation, and the net under it.
-- ---------------------------------------------------------------------------
local verify_generation = 0
local verify_failures = 0
local schedule_verify

-- ---------------------------------------------------------------------------
-- Workspaces: 1 on the panel, every other one on the first external.
-- ---------------------------------------------------------------------------
-- The rules do the placing (see workspaces above); plan() lists them per
-- scheme in bindings_for. Rules are replaced, never accumulated: Hyprland
-- keeps one rule per workspace string (the last add wins), and a disabled
-- handle stops matching, so switching to dynamic turns the previous set off
-- and leaves every workspace where it is. Rebinding happens only when the set
-- changes, since every rule schedules a refresh of all outputs and windows.
local bound_signature = nil
local bound_handles = {}

local function bind_workspaces(bindings)
    local parts = {}
    for _, b in ipairs(bindings) do
        parts[#parts + 1] = b.workspace .. "=" .. b.monitor .. (b.default and "*" or "")
    end
    local signature = table.concat(parts, " ")
    if signature == bound_signature then
        return
    end
    for _, handle in ipairs(bound_handles) do
        pcall(function()
            handle:set_enabled(false)
        end)
    end
    bound_handles = {}
    for _, b in ipairs(bindings) do
        local ok, handle = pcall(hl.workspace_rule, {
            workspace = b.workspace,
            monitor = b.monitor,
            default = b.default or nil,
        })
        if ok and handle then
            bound_handles[#bound_handles + 1] = handle
        end
    end
    bound_signature = signature
end

-- Hyprland applies the rules to existing workspaces only when an output
-- connects. This catches the rest while both are lit: the first external
-- changed and the old one's workspaces fell back to the panel, or a
-- workspace reached the panel by a way no rule covers. Workspace 1 goes
-- first, so the panel has it to show when the others leave.
-- Only two kinds of stray are corrected, as before the schemes: workspace 1
-- away from home, and workspaces sitting on the panel that belong to an
-- external. Ones on another external are left alone (Hyprland's own
-- placement), so a hand move between externals sticks.
local function owner_of(id, p)
    local key = tostring(id)
    for _, b in ipairs(p.bindings) do
        if b.workspace == key then
            return b.monitor
        end
    end
    return nil
end

local function place_workspaces(p)
    local panel = p.place_panel
    local home, away = nil, {}
    for _, ws in ipairs(hl.get_workspaces()) do
        local id = ws.id
        local on = ws.monitor and ws.monitor.name
        -- Special and named workspaces: id below 1 on 0.56, nil upstream since.
        if type(id) == "number" and id >= 1 and on then
            local owner = owner_of(id, p)
            if id == 1 and owner and on ~= owner then
                home = owner
            elseif id ~= 1 and on == panel and owner and owner ~= panel then
                away[#away + 1] = { ws = ws, to = owner }
            end
        end
    end
    if home then
        hl.dispatch(hl.dsp.workspace.move({ workspace = 1, monitor = home }))
    end
    -- An empty workspace lives only while an output shows it, so one the
    -- panel showed is gone once 1 took its place; its object reads nil.
    for _, move in ipairs(away) do
        local monitor = move.ws.monitor
        if monitor and monitor.name == panel and hl.get_monitor(move.to) then
            hl.dispatch(hl.dsp.workspace.move({ workspace = move.ws.id, monitor = move.to }))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Stage two: off, later, only if a lit output remains.
-- ---------------------------------------------------------------------------
local off_generation = 0

-- Invalidates a pending off stage via its generation counter.
local function cancel_off()
    off_generation = off_generation + 1
end

local function off_now(reason, generation)
    if generation ~= off_generation then
        return
    end
    -- Re-read: in the gap an external may have gone, failed its modeset, the
    -- lid may have opened, keep-internal or an override may have changed.
    local state = present()
    local p = plan(state, false)
    if #p.pending == 0 then
        return
    end
    -- Nothing here may take the last lit screen: a panel still lighting is
    -- caught by the evaluation its arrival schedules, which comes back here.
    local remaining = 0
    for _, name in ipairs(state.internal) do
        if not p.off_set[name] then
            remaining = remaining + 1
        end
    end
    for _, name in ipairs(state.external) do
        if not p.off_set[name] then
            remaining = remaining + 1
        end
    end
    if remaining == 0 then
        print("monitors: " .. reason .. ": off stage skipped, nothing would stay lit")
        return
    end
    apply(off_rules(p), reason .. " (off)", "off")
    schedule_verify(policy.panel_off_verify_ms)
end

local function schedule_off(reason)
    off_generation = off_generation + 1
    local generation = off_generation
    hl.timer(function()
        off_now(reason, generation)
    end, { timeout = policy.panel_off_delay_ms, type = "oneshot" })
end

-- ---------------------------------------------------------------------------
-- Gaps, border and rounding per output.
-- ---------------------------------------------------------------------------
-- general.lua sets them for the reference output, the 2560x1440 desk monitor
-- the desktop was tuned on; every lit output gets them scaled by the square
-- root of its logical area over the reference's, the number the bar's
-- Theme.fit uses for its own surfaces, so what Hyprland draws keeps the same
-- share of each screen. Floored at FIT_MIN like Theme.fit: a screen smaller
-- than the reference keeps the reference pixels rather than the share, since
-- the bar became unreadable at the share and the two numbers must agree for
-- the bar's corners to match the windows'. Capped at FIT_MAX against a huge
-- logical screen. A workspace rule with the monitor selector carries
-- the gaps and border (the last rule for a selector wins), a window rule
-- matched on the same selector the rounding. Blur size and shadow range have
-- no per-output form and stay as set. Old handles are switched off before
-- new values go in, since window rules accumulate.
local FIT_REFERENCE = { width = 2560, height = 1440 }
local FIT_MIN, FIT_MAX = 1, 2
-- hl.window_rule refuses a rounding above 20 (0.56.2: "value 27 is more than
-- the maximum of 20"). The refusal is not a Lua error: the pcall below does
-- not catch it, and it comes back as the error of the whole eval that
-- triggered it, so an override set from the shell reported a failure it had
-- in fact applied. The gaps are unbounded; only the corner radius stops
-- growing past a 1.11 fit.
local FIT_ROUNDING_MAX = 20
local fit_base = nil
local fit_applied = {}
local fit_handles = {}

local function read_fit_base()
    local function edge(value)
        if type(value) == "table" then
            return tonumber(value.top) or 0
        end
        return tonumber(value) or 0
    end
    local ok, gaps_in = pcall(hl.get_config, "general.gaps_in")
    local ok_out, gaps_out = pcall(hl.get_config, "general.gaps_out")
    local ok_border, border = pcall(hl.get_config, "general.border_size")
    local ok_round, rounding = pcall(hl.get_config, "decoration.rounding")
    if not (ok and ok_out and ok_border and ok_round) then
        return nil
    end
    return {
        gaps_in = edge(gaps_in),
        gaps_out = edge(gaps_out),
        border = tonumber(border) or 0,
        rounding = tonumber(rounding) or 0,
    }
end

-- From the planned size, so a scale or mode override is answered in the
-- same evaluation; the timer below re-checks against what the output then
-- shows, in case Hyprland corrected the scale.
local function fit_for(name, planned)
    local width, height = logical_size(name, planned)
    if not width then
        return nil
    end
    local f = math.sqrt((width * height) / (FIT_REFERENCE.width * FIT_REFERENCE.height))
    return math.max(FIT_MIN, math.min(FIT_MAX, f))
end

local fit_recheck_generation = 0

-- planned: the sizes this evaluation asks for (true, from evaluate) or the
-- ones the outputs show (false, from the recheck below).
local function apply_fit_rules(state, planned)
    if not fit_base then
        return
    end
    local names = {}
    for _, name in ipairs(state.internal) do
        names[#names + 1] = name
    end
    for _, name in ipairs(state.external) do
        names[#names + 1] = name
    end
    for _, name in ipairs(names) do
        local f = fit_for(name, planned)
        if f then
            local function scaled(v)
                return math.floor(v * f + 0.5)
            end
            local rounding = math.min(FIT_ROUNDING_MAX, scaled(fit_base.rounding))
            local values = string.format("%d/%d/%d/%d", scaled(fit_base.gaps_in), scaled(fit_base.gaps_out),
                scaled(fit_base.border), rounding)
            if fit_applied[name] ~= values then
                local old = fit_handles[name]
                if old then
                    for _, handle in ipairs(old) do
                        pcall(function()
                            handle:set_enabled(false)
                        end)
                    end
                end
                local selector = "m[" .. name .. "]"
                local handles = {}
                local ok, handle = pcall(hl.workspace_rule, {
                    workspace = selector,
                    gaps_in = scaled(fit_base.gaps_in),
                    gaps_out = scaled(fit_base.gaps_out),
                    border_size = scaled(fit_base.border),
                })
                if ok and handle then
                    handles[#handles + 1] = handle
                end
                ok, handle = pcall(hl.window_rule, {
                    name = "fit-rounding-" .. name,
                    match = { workspace = selector },
                    rounding = rounding,
                })
                if ok and handle then
                    handles[#handles + 1] = handle
                end
                fit_handles[name] = handles
                fit_applied[name] = values
                print(string.format("monitors: fit %s x%.2f -> gaps %s", name, f, values))
            end
        end
    end
end

-- Once the rules have had a frame to land, the planned and the shown sizes
-- agree unless Hyprland refused a scale; this catches that case.
local function schedule_fit_recheck()
    fit_recheck_generation = fit_recheck_generation + 1
    local generation = fit_recheck_generation
    hl.timer(function()
        if generation ~= fit_recheck_generation then
            return
        end
        apply_fit_rules(present(), false)
    end, { timeout = 1500, type = "oneshot" })
end

function M.evaluate(reason, at_load)
    local state = present()
    local p = plan(state, at_load)
    bind_workspaces(p.bindings)
    -- Armed before applying, so a watchdog-cut callback still leaves the net.
    -- 1 s instead of verify_ms when the panel went off on sysfs alone: FALLBACK
    -- appears ~2 s in and applies queued rules on its first frame, which a 3 s
    -- verify can miss if the external never materialises. A mitigation for an
    -- unreproduced race, not a proof.
    schedule_verify(p.sysfs_only and math.min(1000, policy.verify_ms) or nil)
    apply(lit_rules(p), reason, "lit")
    apply_fit_rules(state, true)
    schedule_fit_recheck()

    if #p.pending == 0 then
        cancel_off()
        -- Rules for outputs that are off already, or not plugged in yet:
        -- no modeset, so nothing to keep apart from the lighting.
        if #p.off > 0 then
            apply(off_rules(p), reason .. " (off)", "off")
        end
        -- Not at load: the rest of the config has not loaded yet, and at
        -- first launch nothing is lit.
        if not at_load and p.place_panel then
            place_workspaces(p)
        end
        return
    end
    -- At load there is one modeset and nothing to collide with; splitting
    -- would blink the panel on every boot or reload that keeps it off.
    if at_load then
        apply(off_rules(p), reason .. " (off)", "off")
        return
    end
    schedule_off(reason)
end

-- One line the Displays panel parses: the workspace scheme in force and
-- where it came from, the main external and why, the panel holding 1.
-- Read with: hyprctl repl 'return MONITORS.status()'
function M.status()
    local p = plan(present(), false, true)
    return string.format("workspaces=%s source=%s preset=%s main=%s main_reason=%s panel=%s",
        p.ws_scheme, global_override.workspaces and "override" or "preset", policy.workspaces,
        p.ws_external or "-", (p.main_reason or "none"):gsub(" ", "_"), p.ws_panel or "-")
end

-- Re-read the overrides (scripts/monitor-override.sh calls this after
-- writing) and act on them at once.
function M.reload_overrides(reason)
    load_overrides()
    kept_warned = false
    M.evaluate(reason or "overrides", false)
end

-- Safety net: no real output enabled means re-evaluate, which lights the
-- panel. Bounded by verify_limit so an unusable panel is not retried forever.
-- Also armed at load; hyprland.start re-arms it at first launch.
schedule_verify = function(delay_ms)
    verify_generation = verify_generation + 1
    local generation = verify_generation
    hl.timer(function()
        if generation ~= verify_generation then
            return
        end
        if present().real > 0 then
            verify_failures = 0
            return
        end
        verify_failures = verify_failures + 1
        if verify_failures > policy.verify_limit then
            warn("verify: still no output after " .. policy.verify_limit .. " attempts, giving up; ~/recover-desktop from a console")
            return
        end
        print("monitors: verify: no real output is enabled, asking for the built-in panel")
        M.evaluate("verify", false)
    end, { timeout = delay_ms or policy.verify_ms, type = "oneshot" })
end

-- ---------------------------------------------------------------------------
-- Events.
-- ---------------------------------------------------------------------------
-- Each event restarts the settle timer; the last event of a burst evaluates,
-- or settle_max_ms forces one (os.time() 1 s granularity is enough for that).
local settle_generation = 0
local settle_since = nil

local function schedule(reason, delay_ms)
    -- A pending off stage was decided on a state that no longer holds.
    cancel_off()
    local now = os.time()
    settle_since = settle_since or now
    settle_generation = settle_generation + 1
    local generation = settle_generation
    if (now - settle_since) * 1000 >= policy.settle_max_ms then
        settle_since = nil
        M.evaluate(reason .. " (forced)", false)
        return
    end
    hl.timer(function()
        if generation ~= settle_generation then
            return
        end
        settle_since = nil
        M.evaluate(reason, false)
    end, { timeout = delay_ms, type = "oneshot" })
end

hl.on("monitor.added", function(monitor)
    local name = monitor.name
    if name then
        note(name, monitor.description or "")
        -- A re-enabled panel keeps its old DPMS state (maybe off from the
        -- lid); light it unless the lid is shut.
        if classify(name) == "internal" and not lid_closed and hl.get_monitor(name) then
            hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
        end
    end
    -- Now rather than at the settled evaluation: Hyprland moves bound
    -- workspaces right after this event, so an arriving external takes
    -- 2.. from the panel in the same step.
    local p = plan(present(), false)
    bind_workspaces(p.bindings)
    -- An arriving external waits; a synthetic one (FALLBACK: no screen left)
    -- is answered almost at once, since waiting only prolongs the dark.
    local delay = policy.settle_removed_ms
    if name then
        local class = classify(name)
        if class == "external" then
            delay = policy.settle_added_ms
        elseif class == "synthetic" then
            delay = policy.settle_synthetic_ms
        end
    end
    schedule("added " .. tostring(name), delay)
end)

hl.on("monitor.removed", function(monitor)
    schedule("removed " .. tostring(monitor.name), policy.settle_removed_ms)
end)

hl.on("hyprland.start", function()
    M.evaluate("start", false)
end)

-- ---------------------------------------------------------------------------
-- Lid.
-- ---------------------------------------------------------------------------
-- A per-output DPMS request also sets the compositor-wide state (0.56.2), so
-- after an off, with *_enables_dpms on (general.lua), any input would re-light
-- every dark output: the panel in a shut lid, a display the screensaver turned
-- off. Enabling an output that is lit already changes nothing on it and resets
-- that state to on. A dark output is never the one enabled, and with nothing
-- lit the state stays off, so input still wakes a desk that went all dark.
local function rearm_dpms()
    for _, monitor in ipairs(hl.get_monitors()) do
        local name = monitor.name
        if name and monitor.dpms_status and classify(name) ~= "synthetic" then
            hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
            return
        end
    end
end

-- Display only: no suspend, input untouched. DPMS darkens the panel at once;
-- beside an external the evaluation that follows also turns it off, which
-- moves workspace 1 to a screen in view. Alone the panel stays enabled, as
-- re-enabling is a modeset. Per output, and resolved first: dpms with an
-- unresolvable name silently hits every output.
local function dpms_internal(action)
    local state = present()
    for _, name in ipairs(state.internal) do
        if hl.get_monitor(name) then
            hl.dispatch(hl.dsp.dpms({ action = action, monitor = name }))
        end
    end
    if action == "disable" then
        rearm_dpms()
    end
end

function M.lid_close()
    lid_closed = true
    dpms_internal("disable")
    schedule("lid shut", policy.settle_removed_ms)
end

function M.lid_open()
    lid_closed = false
    dpms_internal("enable")
    schedule("lid open", policy.settle_removed_ms)
end

-- Firmware names the ACPI device LID, LIDn or LID_. Probed by name, since
-- listing a directory would need a process; no file reads as an open lid.
local LID_DEVICES = { "LID", "LID0", "LID1", "LID_" }

local function lid_shut_now()
    if not policy.acpi_lid then
        return false
    end
    for _, device in ipairs(LID_DEVICES) do
        local line = read_first_line(policy.acpi_lid .. "/" .. device .. "/state")
        if line then
            return line:find("closed", 1, true) ~= nil
        end
    end
    return false
end

-- After a suspend (hypridle's after_sleep_cmd). No lid event crosses a
-- sleep, so the lid is re-read from ACPI; then the lit externals are woken,
-- the panel only with the lid open (a plain dpms enable lit it inside the
-- closed lid and re-armed the compositor-wide state the lid code keeps off).
-- The evaluation that follows catches outputs that re-enumerated in sleep.
function M.resume()
    lid_closed = lid_shut_now()
    local state = present()
    if not lid_closed then
        for _, name in ipairs(state.internal) do
            if hl.get_monitor(name) then
                hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
            end
        end
    end
    for _, name in ipairs(state.external) do
        if hl.get_monitor(name) then
            hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
        end
    end
    schedule("resume", policy.settle_removed_ms)
end

-- ---------------------------------------------------------------------------
-- Screensaver.
-- ---------------------------------------------------------------------------
-- The bar's screensaver (quickshell/bar/modules/ScreensaverDpms.qml) blacks
-- an unused display out by itself and calls this only once nobody is at the
-- keys, to turn a display off, and when it is used again, to turn it back on.
-- DPMS only: the output stays enabled with its workspaces and windows, and
-- nothing is suspended or locked. While another output is lit, input does
-- not wake the dark one (rearm_dpms); the bar wakes it when focus reaches it.
-- Once every output is dark, the first key or pointer motion wakes them all.
-- The panel in a shut lid stays dark whatever the bar asks.
--
-- Each call stalls the whole compositor (0.56.2, aquamarine 0.15.1, measured
-- on the Lunar Lake panel 2026-10-05): the commit is a blocking modeset on
-- the main thread (about 0.4 s off, 0.6 s on), and every change of an
-- output's enabled state makes aquamarine probe every connector again (up
-- to 1.1 s). Hence the bar's black for a display unused while someone works
-- on another.
--
-- An output already in the state asked for is left alone. The bar asks for
-- every display to be lit whenever it starts or reloads and whenever an
-- output appears (a display an earlier bar left off must not stay off), so
-- most requests are for the state an output already has; none of them is
-- sent on as a DPMS dispatch, which may cost a commit like the one above.
function M.saver(name, off)
    if type(name) ~= "string" then
        return
    end
    local monitor = hl.get_monitor(name)
    if not monitor then
        return
    end
    if off then
        if monitor.dpms_status ~= false then
            hl.dispatch(hl.dsp.dpms({ action = "disable", monitor = name }))
            rearm_dpms()
        end
    elseif monitor.dpms_status ~= true and not (lid_closed and classify(name) == "internal") then
        hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
    end
end

-- Lights every output that is off but the panel in a shut lid. bar.service
-- runs it whenever the bar stops, since nothing else would wake an output
-- the screensaver left off.
function M.saver_release()
    for _, monitor in ipairs(hl.get_monitors()) do
        local name = monitor.name
        if name and not monitor.dpms_status and classify(name) ~= "synthetic"
            and not (lid_closed and classify(name) == "internal") then
            hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Session end.
-- ---------------------------------------------------------------------------
-- scripts/session-power.sh calls prepare_exit before a sign-out or power-off
-- while an external is lit, and cancel_exit when the power-off is refused.
-- The panel goes off in the policy's own separate modeset, as the lid takes
-- it, so the session ends on the external alone.
--
-- Why: on the Lunar Lake laptop this was written on, a power-off with HDMI
-- attached sometimes never reaches S5 and only an EC reset (a long power
-- button hold) ends it. In September 2026, seven sign-outs that ended on the
-- external alone were each followed by a clean power-off from the greeter;
-- of three that ended with the panel lit as well, two were not. The sample
-- is small and the mechanism unknown: this reproduces the state that held,
-- it does not fix a cause.
--
-- An external the screensaver turned off is still enabled, so it counts as
-- lit: the plan turned the panel off beside it, and the session ended with no
-- output lit at all, a state the evidence above never covered. Such an
-- external is lit first. Not the panel, which goes off here anyway: lit and
-- then disabled, it flashed as the session ended.
function M.prepare_exit()
    exiting = true
    for _, monitor in ipairs(hl.get_monitors()) do
        local name = monitor.name
        if name and monitor.dpms_status == false and classify(name) == "external" then
            hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
        end
    end
    M.evaluate("session end", false)
end

function M.cancel_exit()
    if not exiting then
        return
    end
    exiting = false
    M.evaluate("session end cancelled", false)
end

-- ---------------------------------------------------------------------------
-- Load.
-- ---------------------------------------------------------------------------
load_state()
load_overrides()
if policy.sysfs then
    sysfs = sysfs_connectors()
    for name in pairs(sysfs) do
        if classify(name) == "internal" and known[name] == nil then
            known[name] = ""
        end
    end
end
lid_closed = lid_shut_now()
fit_base = read_fit_base()
M.evaluate("load", true)
