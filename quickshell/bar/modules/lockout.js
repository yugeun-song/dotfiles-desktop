.pragma library

// The lock screen's lockout countdown (lock.qml), worked out by pam_faillock's
// own rule from what it reads itself: its lines in the PAM stack, its
// defaults in faillock.conf, and the user's tally as `faillock` lists it.
// Pure, for the tests. PAM still decides: this only says how long to wait.

// Each pam_faillock "preauth" line's step: how many failures (deny), for how
// long they lock (unlock_time, seconds) and how far back they count
// (fail_interval); faillock.conf, then the module's built-in defaults, for
// what a line leaves out. In the order written.
function steps(pamText, confText) {
    const conf = { deny: 3, unlock_time: 600, fail_interval: 900 };
    for (const line of String(confText || "").split("\n")) {
        const m = /^\s*(deny|unlock_time|fail_interval)\s*=\s*(\d+)\s*$/.exec(line);
        if (m)
            conf[m[1]] = Number(m[2]);
    }
    const out = [];
    for (const line of String(pamText || "").split("\n")) {
        const s = line.replace(/#.*/, "");
        if (!/^\s*-?auth\s+\S.*\bpam_faillock\.so\b.*\bpreauth\b/.test(s))
            continue;
        const arg = name => {
            const m = new RegExp(`\\b${name}=(\\d+)`).exec(s);
            return m ? Number(m[1]) : conf[name];
        };
        out.push({ deny: arg("deny"), unlock: arg("unlock_time"), interval: arg("fail_interval") });
    }
    return out;
}

// The tally's valid failures, in ms since the epoch, from `faillock --user`'s
// rows ("2026-11-05 10:55:33 SVC source V"), local time as it prints them.
function failures(listing) {
    const out = [];
    for (const line of String(listing || "").split("\n")) {
        const m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\s.*\s([VI])$/.exec(line.trim());
        if (m && m[7] === "V")
            out.push(new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime());
    }
    return out;
}

// When the account opens again, in ms since the epoch, or 0 when no step
// holds it now: as pam_faillock counts, the failures within a step's
// interval of the latest, and a step reached holds until the latest plus
// its unlock time. A step with no unlock time holds until reset (Infinity).
function until(times, steps, now) {
    if (!times || times.length === 0)
        return 0;
    const latest = Math.max.apply(null, times);
    let end = 0;
    for (const s of steps || []) {
        if (!(s.deny > 0))
            continue;
        const count = times.filter(t => latest - t < s.interval * 1000).length;
        if (count < s.deny)
            continue;
        end = Math.max(end, s.unlock > 0 ? latest + s.unlock * 1000 : Infinity);
    }
    // pam_faillock opens once latest + unlock_time < now, in whole seconds.
    return end >= now ? end : 0;
}

// What is left, as m:ss (minutes may pass 59).
function clock(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
