-- Output policy: which screens are on, at what mode and scale, and what the
-- lid does. It runs inside the compositor.
--
-- The rule is the one the shell script that used to do this implemented:
--
--   any external output   -> the externals are the desktop, the built-in
--                            panel goes off
--   no external output    -> the built-in panel is the desktop
--
-- with keep_internal, in the settings file or as a marker file, meaning
-- "both". What changed is where the rule runs. It used to be a bash watcher
-- on the event socket that called hyprctl; it is now a config module that
-- registers hl.on handlers and emits hl.monitor rules. There is no process,
-- no polling, and no second authority arguing with the config on reload.
--
-- Anything that describes a particular machine -- the scale of its panel,
-- whether it wants both screens -- lives in monitor_settings.lua beside the
-- config, which is not part of the repository. monitor_settings_example.lua
-- is, and documents every field. A settings file that is missing, fails to
-- load, or is not a table is reported once and ignored: every default below
-- is a working desktop on its own.
--
-- Three facts about this Hyprland shape the code. All three were read from
-- the 0.56.2 sources, not from the wiki.
--
--   FALLBACK    When the last enabled output goes away the compositor makes a
--               headless output literally named FALLBACK. It appears in
--               hl.get_monitors() and in monitor.added like a real screen. The
--               old classifier counted it as an external, kept the panel off,
--               and every HDMI unplug ended on a black screen. Anything named
--               FALLBACK or HEADLESS-* is ignored here.
--
--   reload      hyprctl reload throws away every monitor rule and every timer,
--               re-runs this file, and then re-checks each output against the
--               rules. So the policy is evaluated at load time too: a reload
--               while docked emits the panel's disabled rule before that check
--               runs, and the panel stays off instead of blinking on and back
--               off. And the verify timer is armed at load as well, because a
--               reload that lands inside a hotplug has just cancelled the one
--               that was pending.
--
--   idempotent  A rule is compared with the output's current state and one
--               that already matches costs nothing. Every evaluation therefore
--               emits the whole desired state and lets the compositor find the
--               difference. No "already placed" bookkeeping, no parked
--               position: the overlap check only looks at enabled outputs.
--
-- hl.get_monitors() lists enabled outputs only. A disabled panel is invisible
-- to it, and at first launch nothing is visible at all. The panel's name comes
-- from sysfs and its description, which is what the scale setting matches on,
-- from a small state file this module writes. Both are read once per load.
--
-- Two limits, so they are not rediscovered. The verify timer counts outputs
-- the compositor has enabled, not screens that show something: an external
-- that is enabled and dark leaves the panel off, and ~/recover-desktop from a
-- console is the way out. And a wlr-output-management client -- wlr-randr,
-- wdisplays, kanshi -- stores an override the compositor applies on top of
-- every rule for the rest of the session; nothing here can see it. Do not
-- run one alongside this.
--
-- Everything here runs under the compositor's callback budget, which is 50 ms
-- for an event or timer callback. Nothing spawns a process. The only file
-- access on the event path is one io.open of the keep-internal marker; the
-- state file is written from its own timer, so a slow disk cannot take the
-- verify timer with it.
--
-- From outside: hyprctl eval 'MONITORS.evaluate("manual")'

local M = {}
MONITORS = M

-- Hyprland writes no log file unless debug:disable_logs is turned off, so a
-- print() from here is invisible on an ordinary machine. Anything the user
-- has to act on -- a settings file that does not load, a state file that
-- cannot be written, a panel that would not come back -- is also put on the
-- screen. Routine evaluations are only printed.
local function warn(message)
    print("monitors: " .. message)
    pcall(function()
        hl.notification.create({ text = "monitors: " .. message, duration = 10000 })
    end)
end

local SETTINGS_FILE = CONFIG .. "/monitor_settings.lua"
local KEEP_INTERNAL_FILE = CONFIG .. "/keep-internal"
local STATE_FILE = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/hypr/monitors.state"

-- The defaults. The connector type is what makes a panel internal, so no
-- list of this machine's outputs is needed. The synthetic names are the
-- compositor's own and match neither side of the rule.
--
-- Two settle times, because the two directions cost differently. An output
-- that went away leaves the desktop dark until the panel is back, so that is
-- answered fast; only a burst from a cable that is not quite seated is left
-- to settle. An output that arrived leaves both screens on until the panel is
-- switched off, which is harmless, so that waits long enough for a link that
-- is still training, or a display that flaps as it wakes, to stop flapping
-- before the panel is modeset. However long the flapping goes on, an
-- evaluation is forced after settle_max_ms.
local policy = {
    internal = { "^eDP", "^LVDS", "^DSI" },
    synthetic = { "^FALLBACK$", "^HEADLESS%-" },
    scales = {},
    keep_internal = false,
    settle_removed_ms = 400,
    settle_added_ms = 2000,
    -- A synthetic output arriving is the compositor reporting it has no screen
    -- left. Nothing about that improves by waiting, so this is only long
    -- enough to leave the event handler before rules are emitted.
    settle_synthetic_ms = 60,
    settle_max_ms = 6000,
    verify_ms = 3000,
    verify_limit = 5,
    sysfs = true,
    -- Between lighting the externals and darkening the panel. See the two
    -- stages in M.evaluate: these are two modesets and they must not reach
    -- the driver as one commit. The delay is not a settle window -- the
    -- flapping has already settled by the time this is armed -- it is the gap
    -- that keeps the panel's modeset out of the external's.
    panel_off_delay_ms = 700,
    -- How soon after darkening the panel to check that something is still
    -- lit. The ordinary verify at 3 s is a net for a policy that decided
    -- wrongly; this one is a net for the one action in the whole module that
    -- can take the last screen away, so it is checked on its own and sooner.
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

-- Each field is checked on its own, so one bad value falls back to its
-- default and says so, rather than silently taking the whole file down.
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
    -- A pattern that does not compile raises inside string.find, and a raise
    -- while this file loads is a configuration that failed to load: no binds,
    -- emergency mode. So every pattern is tried on an empty string first.
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
                -- The type test comes first: indexing a number raises, and a
                -- raise here is a config that failed to load.
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
                        scale = tostring(scale),
                    }
                end
            end
        end
    end
end

load_settings()

-- A test harness runs this module in a nested compositor, where the only real
-- output is called WAYLAND-1 and the "externals" are headless outputs it
-- creates and destroys. It says so through this global before the module
-- loads, and it wins over the settings file.
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

-- The description Hyprland reports is "make model serial" with commas
-- removed, so a match is a prefix of it ending at a word boundary: the same
-- panel on another connector still matches, a different panel on the same
-- connector does not. An output entry names the connector instead, for the
-- machines where that is the easier thing to know.
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
    return "1"
end

-- ---------------------------------------------------------------------------
-- What outputs exist, whether or not the compositor has one enabled.
-- ---------------------------------------------------------------------------
-- known: name -> description of every real output this machine has shown.
-- The description is what a scale entry matches on, and it is the one thing
-- that cannot be recovered for an output that is not enabled right now. So it
-- is remembered across reloads and launches in STATE_FILE, written only when
-- a pair changes. An entry that is stale, a panel from another machine say,
-- only produces a rule for an output that never appears, which costs nothing.
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

-- Written beside the target and renamed over it: this file is read at the
-- next launch, which may follow a crash. Written from its own timer, never
-- from an event or evaluation, so a disk that stalls cannot cost the verify
-- timer its turn. Reported once if it cannot be written, because the only
-- other symptom is a panel that comes up at scale 1 after a docked boot.
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

-- The connector names the kernel exposes, and whether each has something
-- plugged in. Probed by name rather than listed, because listing a directory
-- needs a process and this must not spawn one. The type names are DRM's own;
-- the ones a laptop or desktop can actually have are enough.
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
                -- Learn it either way; the description is what a scale entry
                -- matches on and it is the same whether the output is drawing.
                note(name, monitor.description or "")
                -- An output the compositor has enabled but cannot drive reports
                -- a zero pixel size: every mode refused by the atomic test (an
                -- untrusted xe modeset, a dock over its bandwidth) or an output
                -- held enabled while dark. It shows nothing, so it is not the
                -- desktop. Counting it would keep the panel off with the screen
                -- black and no way back -- the verify net sees real > 0 and the
                -- reload re-reads the same enabled output. Treated as absent, so
                -- the panel stays on beside it; a later good mode names it real.
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
-- highrr, not preferred: the highest refresh rate the output can do, then the
-- largest resolution at that rate, which is also what the catch-all rule in
-- general.lua asks for, so a rule for an external matches it and costs
-- nothing. Position is left to the compositor except for the first external,
-- which anchors the layout at 0x0 so the bar's notion of "the leftmost screen
-- is the main desktop" holds when both are on.
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

-- The rules are split by one question: does applying it take a screen away?
--
-- Lighting an output is additive and safe in any order. Darkening the panel is
-- not: it is the only rule here that can leave the session with nothing to
-- draw on, and on this machine it also frees a CRTC, which makes the driver
-- reconsider the connector the externals are on. Sent in the same batch as the
-- rule lighting an external, the two modesets arrive as one commit and the
-- compositor passes through a state with no enabled output. On 2026-09-09 it
-- stopped there and stayed for thirteen minutes, alive with its clients still
-- connected; the kernel logged nothing, so nothing was stuck below it.
--
-- So they go out separately, and the panel goes second.

-- Everything that lights a screen. Never a disabled rule.
--
-- With the panel to be turned off this emits no rule for it at all rather than
-- an enabled one: a rule stands until it is replaced, so silence leaves the
-- panel's last rule in force. That is what keeps the two stages idempotent
-- together, and what stops the panel blinking on between them on a reload.
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

-- The panel, alone.
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

-- One remembered summary per stage, because the two now print separately and a
-- single one would make each stage look like a change every time the other ran.
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
-- sysfs is consulted at load time only, and only at first launch, which is
-- the one moment the compositor shows no output and no workspace: a docked
-- boot then never enables the panel in the first place. Any later reload
-- that finds no output is a hotplug in progress, and there the kernel's
-- "connected" is not evidence of a working screen: a cable that is plugged
-- in but refused by the compositor must leave the panel on, and only the
-- compositor's own list says which it is.
local sysfs = {}
local verify_generation = 0
local verify_failures = 0
local schedule_verify

-- ---------------------------------------------------------------------------
-- Stage two: the panel goes off on its own, later, and only if the externals
-- are still there when the moment comes.
-- ---------------------------------------------------------------------------
local panel_off_generation = 0

-- Drops a panel-off that is armed and has not run. Called wherever the world
-- moved under the decision that armed it: a new hotplug burst, a synthetic
-- output appearing, an evaluation that decided the panel stays on. The
-- generation counter is the same mechanism the settle and verify timers use;
-- a timer that finds its generation stale returns without doing anything.
local function cancel_panel_off()
    panel_off_generation = panel_off_generation + 1
end

local function panel_off_now(reason, generation)
    if generation ~= panel_off_generation then
        return
    end
    -- Re-read rather than trust what stage one saw. In the gap the cable can
    -- have been pulled, the external can have failed its modeset and dropped
    -- to zero pixels, or the keep-internal marker can have appeared. In any of
    -- those the panel is the only screen left, so it stays on and this does
    -- nothing.
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
    -- Armed before anything is applied, so a callback cut short by the
    -- compositor's watchdog still leaves the net in place.
    --
    -- Faster when this load turned the panel off on sysfs evidence alone, with
    -- no output enabled yet. The compositor is about to build its FALLBACK
    -- output ~2 s after it is ready, and FALLBACK's first frame applies the
    -- rules queued by then and is torn down in the same idle batch by its own
    -- start listener. If the external the kernel reported never becomes a real
    -- output (cable pulled between sysfs and the DRM scan, a mode the
    -- compositor refuses), the default 3 s verify can miss that frame and the
    -- screen stays black. A 1 s verify puts the panel-enable rule in the queue
    -- in time. This is a mitigation for a race that could not be reproduced
    -- deterministically, not a proof it cannot happen.
    local panel_off = externals_present and not keep_internal()
    schedule_verify(sysfs_only and math.min(1000, policy.verify_ms) or nil)
    apply(lit_rules(state, panel_off), reason, "lit")

    if not panel_off then
        cancel_panel_off()
        return
    end
    -- At load there is nothing on screen to lose: no output enabled, no
    -- workspace, no window to move off the panel. There is only one modeset,
    -- so there is nothing for a second one to collide with, and splitting them
    -- here would instead light the panel for the length of the delay on every
    -- docked boot -- the blink this module already went to some trouble to
    -- remove. The split is for the running compositor only.
    if at_load then
        apply(panel_rules(), reason .. " (panel off)", "panel")
        return
    end
    schedule_panel_off(reason)
end

-- The safety net. Whatever the policy decided, a session with no real output
-- enabled is a laptop with its lid open and nothing on it, and there is no
-- way back from that with a keyboard nobody can see. Bounded, because an
-- output that cannot be enabled at all would otherwise be asked for forever.
-- Armed at load as well; should the event loop not be up yet at first
-- launch, the hyprland.start evaluation arms another.
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
-- Every add and remove restarts the settle timer with the delay its direction
-- calls for; only the last event in a burst evaluates, unless the burst has
-- gone on for settle_max_ms, in which case the state it is in gets applied.
-- os.time() is wall-clock at one-second granularity, which is all the cap
-- needs to be.
local settle_generation = 0
local settle_since = nil

local function schedule(reason, delay_ms)
    -- An event means the world moved. A panel-off armed by the previous
    -- evaluation was decided against a state that no longer holds, and letting
    -- it fire behind the new evaluation is how the panel would go off just as
    -- the external it was making way for went away.
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
        -- A panel the policy brings back keeps whatever DPMS state it had
        -- when it was switched off, which may be "off" from a lid that was
        -- shut at the time. Lit here unless the lid is shut now; behind a
        -- shut lid it stays as it is. The lid flag is this module's own and
        -- resets to open on reload, which errs towards a lit screen.
        if classify(name) == "internal" and not lid_closed and hl.get_monitor(name) then
            hl.dispatch(hl.dsp.dpms({ action = "enable", monitor = name }))
        end
    end
    -- An arriving external waits. Anything else is the panel's cue to come
    -- back, and how fast depends on what arrived.
    --
    -- A synthetic output is not a screen. It is the compositor saying it has
    -- run out of them, which is the one state this module exists to get out
    -- of, and it is not a state a settle window can improve: the window is
    -- there to absorb a cable that is not quite seated, and no amount of
    -- waiting turns FALLBACK into a display. Waiting there is what left the
    -- session dark for the length of the window on every unplug, and on
    -- 2026-09-09 the compositor never came out of that state at all.
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
-- Only the display: input devices are untouched, so the keyboard keeps
-- working with the lid shut, and nothing here suspends. DPMS rather than
-- disabling the output, because bringing an output back is a modeset and DPMS
-- is not. Named per output, so with keep_internal and an external attached
-- the lid still darkens exactly the panel behind it. The name is resolved
-- first: the dpms dispatcher given a name it cannot resolve acts on every
-- output, silently, and that is not a lid.
--
-- One more thing the compositor does with a per-output DPMS request, read
-- from 0.56.2: it records the requested state as the compositor-wide one.
-- With misc.key_press_enables_dpms and mouse_move_enables_dpms on (they are,
-- see general.lua) the next key or pointer event then re-lights every output,
-- panel included. So after the panel goes dark, an enable is sent to an
-- external that is already lit -- a no-op for that output -- to put the
-- compositor-wide record back to "on". With no external there is nothing to
-- send it to, and the panel wakes on the next key as it always did.
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
