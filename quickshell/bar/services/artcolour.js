.pragma library

// The colour a cover lends the island's meter (services/Media.qml), shared
// with the lock screen's notch, its bars coloured from the card's cover
// (LockCard.qml), which runs in a process of its own and must not start the
// bar's Media there: its cover fetch would write the bar's files. Plain functions of their arguments, in OKLCH.

function lch(c) {
    const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    const r = lin(c.r), g = lin(c.g), b = lin(c.b);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    return { l: L, c: Math.hypot(A, B), h: (Math.atan2(B, A) * 180 / Math.PI + 360) % 360 };
}

function fromLch(L, C, h) {
    const enc = v => v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
    const rgb = chroma => {
        const A = chroma * Math.cos(h * Math.PI / 180);
        const B = chroma * Math.sin(h * Math.PI / 180);
        const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
        const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
        const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3);
        return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
    };
    let lo = 0, hi = C, out = rgb(0);
    for (let k = 0; k < 16; ++k) {
        const mid = (lo + hi) / 2;
        const v = rgb(mid);
        if (v.every(x => x >= -0.0005 && x <= 1.0005)) {
            lo = mid;
            out = v;
        } else {
            hi = mid;
        }
    }
    const inside = rgb(C);
    if (inside.every(x => x >= -0.0005 && x <= 1.0005))
        out = inside;
    const clamp = x => Math.max(0, Math.min(1, enc(Math.max(0, x))));
    return Qt.rgba(clamp(out[0]), clamp(out[1]), clamp(out[2]), 1);
}

function vivid(colors, anchors, fallback) {
    let best = null;
    let bestScore = 0;
    for (const c of colors ?? []) {
        const p = lch(c);
        // Hue from a swatch with colour in it, not from near black or white.
        const score = p.c * (1 - Math.abs(p.l - 0.65));
        if (p.c >= 0.05 && score > bestScore) {
            best = p;
            bestScore = score;
        }
    }
    if (best === null || anchors.length === 0)
        return fallback;
    const a = anchors;
    let i = a.findIndex(x => x.h > best.h);
    if (i < 0)
        i = 0;
    const hi = a[i];
    const lo = a[(i + a.length - 1) % a.length];
    const span = (hi.h - lo.h + 360) % 360 || 360;
    const t = ((best.h - lo.h + 360) % 360) / span;
    return fromLch(lo.l + (hi.l - lo.l) * t, lo.c + (hi.c - lo.c) * t, best.h);
}
