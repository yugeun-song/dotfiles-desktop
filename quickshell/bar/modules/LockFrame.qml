import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// A screen of the lock (lock.qml), as the lock screen (LockScreen) and the
// see-through lock (LockGlass) both lay it out: hyprlock.conf's design as
// lock-spec.py hands it over for this screen, in its pixels, read as hyprlock
// reads its numbers, so the lockers draw alike: a label's or a picture's
// position is from the screen's middle (up is positive) or, at the top, its
// top edge down from the screen's; font sizes are points at 96 dpi. A screen
// the spec has no fitted copy for (one plugged in while locked) takes the
// design's numbers fitted here as lock-fit.sh fits them.
Item {
    id: root

    required property ShellScreen lockScreen
    required property var lockRoot

    readonly property var spec: root.lockRoot.spec
    // The compositor's scale, not Qt's ratio, which rounds a fractional one.
    readonly property real scaleOf: Hyprland.monitorFor(root.lockScreen)?.scale ?? root.lockScreen?.devicePixelRatio ?? 1
    readonly property int deviceW: Math.round(root.width * root.scaleOf)
    readonly property int deviceH: Math.round(root.height * root.scaleOf)

    // The output's own numbers, which lock-fit.sh sized for its mode at this
    // lock, taken to this item's pixels by the mode's width; else the
    // design's, with this screen's factors.
    readonly property var fitted: {
        const s = root.spec;
        if (!s || !s.outputs || root.width <= 0 || root.height <= 0)
            return null;
        const own = s.outputs[root.lockScreen?.name ?? ""];
        if (own && own.mode && own.mode[0] > 0)
            return { o: own, fit: 1, wide: 1, unit: root.width / own.mode[0] };
        const design = Object.values(s.outputs).find(o => !o.mode) ?? own;
        if (!design || root.deviceW <= 0 || root.deviceH <= 0)
            return null;
        const fx = root.deviceW / s.reference[0];
        const fy = root.deviceH / s.reference[1];
        const u = Math.min(fx, fy) * s.scale;
        const st = Math.max(1, Math.min(s.stretch_max, fx / fy));
        return { o: design, fit: u, wide: u * st, unit: 1 / root.scaleOf };
    }
    readonly property var o: root.fitted?.o ?? ({})

    // A height, a font size or an even width, and a width, in this item's
    // (logical) pixels.
    function tall(v: real): real {
        return v * (root.fitted?.fit ?? 1) * (root.fitted?.unit ?? 1);
    }

    function wide(v: real, even: bool): real {
        return v * (even ? (root.fitted?.fit ?? 1) : (root.fitted?.wide ?? 1)) * (root.fitted?.unit ?? 1);
    }

    // A point size at 96 dpi as pixels here.
    function points(pt: real): real {
        return root.tall(pt) * 96 / 72;
    }

    // A place on the screen's own pixel grid: the ink's layers are drawn at
    // the screen's scale, and one laid between two pixels came out jagged or
    // soft (LockLabel).
    function crisp(v: real): real {
        return Math.round(v * root.scaleOf) / root.scaleOf;
    }

    // A length of whole screen pixels, at least v: the room inside a layer,
    // so what it holds starts on a pixel too.
    function whole(v: real): real {
        return Math.ceil(v * root.scaleOf) / root.scaleOf;
    }

    function xOf(block: var, w: real): real {
        const x = root.wide(block?.position?.[0] ?? 0, block?.even ?? false);
        return block?.halign === "left" ? x : block?.halign === "right" ? root.width - w + x : (root.width - w) / 2 + x;
    }

    function yOf(block: var, h: real): real {
        const y = root.tall(block?.position?.[1] ?? 0);
        return block?.valign === "top" ? -y : block?.valign === "bottom" ? root.height - h - y : (root.height - h) / 2 - y;
    }

    // hyprlock.conf names faces ("Inter Bold"), but hyprlock takes the whole
    // name as a family, finds none of that name and draws Inter's regular:
    // the look the user chose (2026-10-24 to 2026-11-02) is the regular
    // weight, so that is what this draws, the family without the face.
    function family(name: string): string {
        return (name ?? "").replace(/ (Thin|ExtraLight|Light|Regular|Medium|SemiBold|Bold|ExtraBold|Black)$/, "") || Theme.uiFont;
    }

    function weight(name: string): int {
        return Font.Normal;
    }
}
