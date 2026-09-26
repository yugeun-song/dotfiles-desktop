-- Output policy, run inside the compositor as hl.on handlers emitting
-- hl.monitor rules (no process, no polling):
--
--   any external output   -> externals are the desktop, built-in panel off
--   no external output    -> built-in panel is the desktop
--
-- keep_internal (setting or marker file) means both. Machine specifics live in
-- monitor_settings.lua (see monitor_settings_example.lua); a bad or missing
-- file is reported and ignored, and every default is a working desktop.
--
-- Facts from the Hyprland 0.56.2 sources that shape the code:
--
--   FALLBACK    When the last output goes, the compositor creates a headless
--               output named FALLBACK that shows up like a real screen. Counted
--               as external it kept the panel off (black screen on unplug), so
--               FALLBACK and HEADLESS-* are ignored.
--
--   reload      hyprctl reload drops all monitor rules and timers, re-runs this
--               file, then re-checks outputs. So the policy also runs at load
--               (a docked reload keeps the panel off without blinking) and the
--               verify timer is re-armed there.
--
--   idempotent  A rule matching current state costs nothing, so each
--               evaluation emits the full desired state; no bookkeeping.
--
-- hl.get_monitors() lists enabled outputs only, so the panel name comes from
-- sysfs and its description (for scale matching) from STATE_FILE.
--
-- Limits: verify counts enabled outputs, not visible ones; an enabled but
-- dark external leaves the panel off (use ~/recover-desktop from a console).
-- A wlr-output-management client (wlr-randr, wdisplays, kanshi) overrides
-- every rule for the session unseen; do not run one alongside this.
--
-- Callbacks must fit the 50 ms budget: nothing spawns, and the only file I/O
-- on the event path is one open of the keep-internal marker.
--
-- Manual run: hyprctl eval 'MONITORS.evaluate("manual")'

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
local KEEP_INTERNAL_FILE = CONFIG .. "/keep-internal"
local STATE_FILE = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/hypr/monitors.state"

-- Defaults. Connector type decides internal vs external. Removal settles
-- fast (the desktop is dark until the panel returns); arrival settles long
-- (both screens on is harmless, a training link may flap). settle_max_ms
-- forces an evaluation during endless flapping.
-- settle_synthetic_ms, panel_off_* and sysfs are not settable from the
-- settings file (see load_settings).
local policy = {
    internal = { "^eDP", "^LVDS", "^DSI" },
    synthetic = { "^FALLBACK$", "^HEADLESS%-" },
    scales = {},
    keep_internal = false,
    settle_removed_ms = 400,
    settle_added_ms = 2000,
    -- FALLBACK means no screen is left; waiting cannot help. Just long
    -- enough to leave the event handler.
    settle_synthetic_ms = 60,
    settle_max_ms = 6000,
    verify_ms = 3000,
    verify_limit = 5,
    sysfs = true,
    -- Gap between lighting externals and darkening the panel, so the two
    -- modesets never reach the driver as one commit (see M.evaluate).
    panel_off_delay_ms = 700,
    -- Sooner check after panel-off, the one action that can remove the last
    -- screen.
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
local function load_settings()
    local chunk, err = loadfile(SETTINGS_FILE)
    if not chunk then
        local f = io.open(SETTINGS_FILE, "r")
        if f then
            f:close()
            warn(SETTINGS_FILE .. " could not be loaded, using defaults: " .. tostring(err))
        end
        return
    end
    local ok, settings = pcall(chunk)
    if not ok then
        warn(SETTINGS_FILE .. " failed to run, using defaults: " .. tostring(settings))
        return
    end
    if type(settings) ~= "table" then
        warn(SETTINGS_FILE .. " must return a table, using defaults")
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
            warn(string.format("%s: %s must be %s, using the default", SETTINGS_FILE, key, describe))
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

    if settings.scales ~= nil then
        local scales = settings.scales
        -- One entry written without the surrounding list is the obvious slip.
        if type(scales) == "table" and (scales.match ~= nil or scales.output ~= nil) then
            scales = { scales }
        end
        if type(scales) ~= "table" then
            warn(SETTINGS_FILE .. ": scales must be a list, using the default")
        else
            for i, entry in ipairs(scales) do
                -- Type test first: indexing a non-table raises at load.
                local scale = type(entry) == "table" and tonumber(entry.scale) or nil
                local match = type(entry) == "table" and entry.match or nil
                local output = type(entry) == "table" and entry.output or nil
                if type(entry) ~= "table" or not scale or scale <= 0
                    or (match == nil and output == nil)
                    or (match ~= nil and type(match) ~= "string")
                    or (output ~= nil and type(output) ~= "string") then
                    warn(string.format("%s: scales[%d] needs match or output, and a positive scale; ignored", SETTINGS_FILE, i))
                else
                    policy.scales[#policy.scales + 1] = {
                        match = match and (match:gsub(",", "")) or nil,
                        output = output,
                        scale = scale,
                    }
                end
            end
        end
    end
end

load_settings()

-- Set by scripts/monitors-selftest.sh (nested compositor: WAYLAND-1 is the
-- panel, HEADLESS-* the externals). Wins over the settings file.
if type(MONITOR_POLICY_OVERRIDE) == "table" then
    for key, value in pairs(MONITOR_POLICY_OVERRIDE) do
        policy[key] = value
    end
end

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

local function exists(path)
    local f = io.open(path, "r")
    if not f then
        return false
    end
    f:close()
    return true
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

-- The description is "make model serial" without commas; match is a prefix
-- ending at a word boundary.
local function scale_for(name, description)
    for _, entry in ipairs(policy.scales) do
        if entry.output and entry.output == name then
            return entry.scale
        end
        if entry.match and description and description ~= "" then
            if description == entry.match or description:sub(1, #entry.match + 1) == entry.match .. " " then
                return entry.scale
            end
        end
    end
    return 1
end

-- ---------------------------------------------------------------------------
-- What outputs exist, whether or not the compositor has one enabled.
-- ---------------------------------------------------------------------------
-- known: name -> description of every real output seen. A disabled output's
-- description cannot be queried, so it persists in STATE_FILE. Stale entries
-- only yield rules for outputs that never appear, which is harmless.
local known = {}

local function load_state()
    local lines = read_lines(STATE_FILE)
    if not lines then
        return
    end
    for _, line in ipairs(lines) do
        local name, description = line:match("^([^\t]+)\t(.*)$")
        if name then
            known[name] = description
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
        f:write(name, "\t", known[name], "\n")
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
    if description == "" and known[name] ~= nil then
        return
    end
    if known[name] == description then
        return
    end
    known[name] = description
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
                local f = io.open(string.format("/sys/class/drm/card%d-%s/status", card, name), "r")
                if f then
                    local status = f:read("l") or ""
                    f:close()
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
-- The desired state, as rules.
-- ---------------------------------------------------------------------------
-- highrr matches the catch-all in general.lua, so it costs nothing. The
-- first external is pinned at 0x0: the bar treats the leftmost screen as main.
local function enabled_rule(name, position)
    return {
        output = name,
        disabled = false,
        mode = "highrr",
        position = position,
        scale = scale_for(name, known[name]),
    }
end

local function keep_internal()
    return policy.keep_internal or exists(KEEP_INTERNAL_FILE)
end

-- Lighting is safe in any order; darkening the panel is not. It frees a
-- CRTC, and batched with an external's enable the two modesets become one
-- commit through a no-output state, where the compositor once stayed wedged.
-- So the panel goes off separately, second.

-- Enabling rules only. With panel_off, the panel gets no rule at all, so its
-- last rule stands and it does not blink on between stages or on reload.
local function lit_rules(state, panel_off)
    local rules = {}
    for i, name in ipairs(state.external) do
        rules[#rules + 1] = enabled_rule(name, i == 1 and "0x0" or "auto")
    end
    if not panel_off then
        for name in pairs(known) do
            if classify(name) == "internal" then
                rules[#rules + 1] = enabled_rule(name, "auto")
            end
        end
    end
    table.sort(rules, function(a, b)
        return a.output < b.output
    end)
    return rules
end

local function panel_rules()
    local rules = {}
    for name in pairs(known) do
        if classify(name) == "internal" then
            rules[#rules + 1] = { output = name, disabled = true }
        end
    end
    table.sort(rules, function(a, b)
        return a.output < b.output
    end)
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
            parts[#parts + 1] = string.format("%s:%s/%s/x%s", rule.output, rule.mode, rule.position, rule.scale)
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
-- sysfs counts only at first launch (no output, no workspace), so a docked
-- boot never lights the panel. Later, "connected" does not prove a working
-- screen; only the compositor's list decides.
local sysfs = {}
local verify_generation = 0
local verify_failures = 0
local schedule_verify

-- ---------------------------------------------------------------------------
-- Stage two: panel off, later, only if the externals are still there.
-- ---------------------------------------------------------------------------
local panel_off_generation = 0

-- Invalidates a pending panel-off via its generation counter.
local function cancel_panel_off()
    panel_off_generation = panel_off_generation + 1
end

local function panel_off_now(reason, generation)
    if generation ~= panel_off_generation then
        return
    end
    -- Re-read: in the gap the external may have gone, failed its modeset, or
    -- keep-internal may have appeared.
    local state = present()
    if #state.external == 0 or keep_internal() then
        return
    end
    apply(panel_rules(), reason .. " (panel off)", "panel")
    schedule_verify(policy.panel_off_verify_ms)
end

local function schedule_panel_off(reason)
    panel_off_generation = panel_off_generation + 1
    local generation = panel_off_generation
    hl.timer(function()
        panel_off_now(reason, generation)
    end, { timeout = policy.panel_off_delay_ms, type = "oneshot" })
end

function M.evaluate(reason, at_load)
    local state = present()
    local externals_present = #state.external > 0
    local sysfs_only = false
    if at_load and state.real == 0 and #hl.get_monitors() == 0 and #hl.get_workspaces() == 0 then
        for name, connected in pairs(sysfs) do
            if connected and classify(name) == "external" then
                externals_present = true
                sysfs_only = true
            end
        end
    end
    -- Armed before applying, so a watchdog-cut callback still leaves the net.
    -- 1 s instead of verify_ms when the panel went off on sysfs alone: FALLBACK
    -- appears ~2 s in and applies queued rules on its first frame, which a 3 s
    -- verify can miss if the external never materialises. A mitigation for an
    -- unreproduced race, not a proof.
    local panel_off = externals_present and not keep_internal()
    schedule_verify(sysfs_only and math.min(1000, policy.verify_ms) or nil)
    apply(lit_rules(state, panel_off), reason, "lit")

    if not panel_off then
        cancel_panel_off()
        return
    end
    -- At load there is one modeset and nothing to collide with; splitting
    -- would blink the panel on every docked boot.
    if at_load then
        apply(panel_rules(), reason .. " (panel off)", "panel")
        return
    end
    schedule_panel_off(reason)
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
    -- A pending panel-off was decided on a state that no longer holds.
    cancel_panel_off()
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

local lid_closed = false

hl.on("monitor.added", function(monitor)
    local name = monitor.name
    if name then
        note(name, monitor.description or "")
        -- A re-enabled panel keeps its old DPMS state (maybe off from the
        -- lid); light it unless the lid is shut. lid_closed resets to open on
        -- reload, erring towards a lit screen.
        if classify(name) == "internal" and not lid_closed and hl.get_monitor(name) then
            hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
        end
    end
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
-- Display only: no suspend, input untouched. DPMS, not disable, because
-- re-enabling is a modeset. Per output, and resolved first: dpms with an
-- unresolvable name silently hits every output.
-- A per-output DPMS request also sets the compositor-wide state (0.56.2), so
-- with *_enables_dpms on (general.lua) any input would re-light the panel.
-- Enabling an already-lit external afterwards resets that state to on.
local function dpms_internal(action)
    local state = present()
    for _, name in ipairs(state.internal) do
        if hl.get_monitor(name) then
            hl.dispatch(hl.dsp.dpms({ action = action, monitor = name }))
        end
    end
    if action == "disable" and state.external[1] and hl.get_monitor(state.external[1]) then
        hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = state.external[1] }))
    end
end

function M.lid_close()
    lid_closed = true
    dpms_internal("disable")
end

function M.lid_open()
    lid_closed = false
    dpms_internal("enable")
end

-- ---------------------------------------------------------------------------
-- Load.
-- ---------------------------------------------------------------------------
load_state()
if policy.sysfs then
    sysfs = sysfs_connectors()
    for name in pairs(sysfs) do
        if classify(name) == "internal" and known[name] == nil then
            known[name] = ""
        end
    end
end
M.evaluate("load", true)
