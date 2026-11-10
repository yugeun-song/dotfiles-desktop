pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services

// The wallpaper, picked from a grid (the user asked for a picker, 2026-11-04), on
// a card over the screen as the weather's place panel is: the desktop's and
// the lock screen's pictures now, what a pick sets (either or both, rung in
// the accent above), and the pictures in ~/Pictures/Wallpapers, newest
// first. A click previews, Apply keeps, Cancel takes it back (the user: try
// it first, and withdraw it). The preview is the shell's own: the picture
// drawn over the wallpaper and under the windows on every screen, decoded
// at the screen's size, so hyprpaper is not touched until Apply, and
// Cancel, Esc or a click beside the card leaves the desktop exactly as it
// was. The lock screen cannot be shown, so its tile above previews it. Apply
// sets it through hypr/scripts/wallpaper.sh, which converts and stores it as
// from the command line. A lock closes the picker. Opened from the control
// centre, or by the key keybinds.lua gives it.
//
// Videos are listed with the pictures, shown by their first frame and
// marked with a play badge; wallpaper.sh plays them (see there).
//
// Nothing is held while it is shut: the folder is read and the thumbnails
// decoded, small and off the UI thread, only while it is open, and only
// those in view.
Scope {
    id: root

    property bool open: false
    // "desktop", "lock" or "both"; kept between openings.
    property string target: "both"
    // wallpaper.sh's DIR, DESK and LOCK: keep in step with it.
    readonly property string folder: (Quickshell.env("HOME") ?? "") + "/Pictures/Wallpapers"
    readonly property string deskFile: root.folder + "/current-desktop.png"
    readonly property string lockFile: root.folder + "/current-lockscreen.png"
    // The freedesktop thumbnail cache's 256 px size, twice a tile or more.
    readonly property string thumbnails: (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") ?? "") + "/.cache"))
                                         + "/thumbnails/large"
    // Bumped when a pick has landed, so the pictures above read the files again.
    property int stamp: 0
    property string status: ""
    // The picture previewed, until Apply or Cancel; "" for none.
    property string candidate: ""
    readonly property bool previewing: root.candidate !== ""

    // Videos too (wallpaper.sh plays them, the user, 2026-11-05): shown by
    // their first frame, which is what wallpaper.sh stores for them, made
    // here with ffmpeg where no thumbnailer has: small for a tile, whole for
    // a candidate on the desktop.
    readonly property var videoPattern: /\.(mp4|webm|mkv|mov|m4v)$/i
    function isVideo(path: string): bool {
        return root.videoPattern.test(path ?? "");
    }
    readonly property string posters: (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") ?? "") + "/.cache"))
                                      + "/quickshell-bar/posters"
    readonly property bool candidateVideo: root.isVideo(root.candidate)
    property string candidateFrame: ""
    readonly property string candidateUrl: !root.previewing ? "" : root.candidateVideo ? root.candidateFrame : "file://" + root.candidate

    onCandidateChanged: {
        root.candidateFrame = "";
        frameMaker.running = false;
        if (root.candidateVideo) {
            frameMaker.out = `${root.posters}/${Qt.md5(root.candidate)}-whole.png`;
            frameMaker.command = ["sh", "-c",
                'mkdir -p -- "${2%/*}" && ffmpeg -loglevel error -nostdin -y -i "$1" -frames:v 1 "$2.part.png" && mv -f -- "$2.part.png" "$2"',
                "sh", root.candidate, frameMaker.out];
            frameMaker.running = true;
        }
    }

    Process {
        id: frameMaker

        property string out: ""

        onExited: code => {
            if (code === 0 && root.candidateVideo)
                root.candidateFrame = "file://" + frameMaker.out;
        }
    }

    function show(): void {
        if (!Surfaces.mayOpen("wallpaper"))
            return;
        root.status = "";
        root.candidate = "";
        root.open = true;
    }

    // Shut without Apply is Cancel; an Apply under way finishes, and its
    // preview stays until the desktop shows the picture.
    function close(): void {
        if (!setter.running)
            root.candidate = "";
        root.open = false;
    }

    function cancel(): void {
        if (!setter.running)
            root.candidate = "";
    }

    function apply(): void {
        if (root.previewing)
            root.pick(root.candidate);
    }

    function toggle(): void {
        if (root.open)
            root.close();
        else
            root.show();
    }

    function pick(path: string): void {
        if (setter.running)
            return;
        const args = root.target === "desktop" ? ["--desktop", path]
                   : root.target === "lock" ? ["--lock", path] : [path];
        setter.command = [Paths.hyprScripts + "/wallpaper.sh"].concat(args);
        root.status = "Setting…";
        setter.running = true;
    }

    // Transient, one panel at a time (services/Surfaces.qml).
    onOpenChanged: Surfaces.report("wallpaper", root.open)

    Connections {
        target: Surfaces

        function onShut(name) {
            if (name === "wallpaper")
                root.close();
        }
    }

    // A lock takes the keyboard; the picker would hold it again after.
    Connections {
        target: KeyFeed

        function onLockedChanged() {
            if (KeyFeed.locked)
                root.close();
        }
    }

    GlobalShortcut {
        name: "wallpaper"
        description: "Pick the wallpaper"
        onPressed: root.toggle()
    }

    // Here, not in the window: a pick runs to its end when the picker shuts.
    Process {
        id: setter

        onExited: code => {
            root.status = code === 0 ? "" : "Could not set the picture";
            root.stamp += 1;
            root.candidate = "";
        }
    }

    // The desktop's preview, on each screen while a picture is previewed for
    // it: above hyprpaper, below the windows, taking no input.
    Variants {
        model: root.previewing && root.target !== "lock" ? Quickshell.screens : []

        PanelWindow {
            required property var modelData

            screen: modelData
            color: "black"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:wallpaper-preview"
            mask: Region {}

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // As hyprpaper covers a screen, at no more than its pixels, the
            // scaled panel's included.
            Image {
                anchors.fill: parent
                source: root.candidateUrl
                sourceSize.width: Math.round(parent.width * (modelData?.devicePixelRatio ?? 1))
                sourceSize.height: Math.round(parent.height * (modelData?.devicePixelRatio ?? 1))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
            }
        }
    }

    // What a pick sets, as a segmented choice.
    component Choice: Rectangle {
        id: choice

        required property string value
        required property string label
        readonly property bool chosen: root.target === choice.value

        width: caption.implicitWidth + Theme.px(28)
        height: Theme.px(30)
        radius: height / 2
        color: choice.chosen ? Theme.menuHighlight : area.containsMouse ? Theme.surfaceRaisedHover : "transparent"

        Text {
            id: caption

            anchors.centerIn: parent
            text: choice.label
            font.family: Theme.uiFont
            font.pixelSize: Theme.menuItemTextSize
            font.weight: choice.chosen ? Font.DemiBold : Font.Normal
            color: choice.chosen ? Theme.menuHighlightText : Theme.fg
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.target = choice.value
        }
    }

    // One of the two pictures now, rung while a pick would set it, and the
    // picture previewed in its place while one is.
    component Now: Column {
        id: now

        required property string file
        required property string label
        required property bool targeted
        property real tileWidth: 0

        readonly property bool previewed: root.previewing && now.targeted
        // The file itself, not a cached thumbnail: a pick rewrites it under
        // the same name, and a thumbnail would show the last one.
        readonly property string url: now.previewed ? root.candidateUrl : "file://" + now.file

        spacing: Theme.px(6)

        Rectangle {
            width: now.tileWidth
            height: Theme.wallpaperNowHeight
            radius: Theme.wallpaperRadius + Theme.wallpaperRing
            color: now.targeted ? Theme.menuHighlight : "transparent"

            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: Theme.wallpaperRing
                radius: Theme.wallpaperRadius
                color: Theme.surfaceWell

                Image {
                    id: nowImage

                    anchors.fill: parent
                    source: now.url
                    sourceSize.width: Math.round(now.tileWidth * 2)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true

                    // Read again once a pick has landed; a URL with a fragment
                    // to force that loaded nothing.
                    Connections {
                        target: root

                        function onStampChanged() {
                            nowImage.source = "";
                            nowImage.source = Qt.binding(() => now.url);
                        }
                    }
                }
            }
        }

        Text {
            text: now.previewed ? `${now.label} · preview` : now.label
            font.family: Theme.uiFont
            font.pixelSize: Theme.menuItemTextSize
            color: now.targeted ? Theme.fg : Theme.muted
        }
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win

            screen: Screens.focused
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:wallpaper"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property real fit: Theme.fit(win.screen)

            FolderListModel {
                id: pictures

                folder: "file://" + root.folder
                nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.mp4", "*.webm", "*.mkv", "*.mov", "*.m4v"]
                caseSensitive: false
                showDirs: false
                sortField: FolderListModel.Time
            }

            // wallpaper.sh's own stored copies are what is shown now, not
            // pictures to pick; its half-written ones end in .new-<pid> and
            // match no filter.
            readonly property var choices: {
                const out = [];
                for (let i = 0; i < pictures.count; i++) {
                    const name = pictures.get(i, "fileName");
                    if (name === "current-lockscreen.png" || name === "current-desktop.png")
                        continue;
                    out.push({ name: name, path: pictures.get(i, "filePath"), modified: String(pictures.get(i, "fileModified")) });
                }
                return out;
            }

            FittedStage {
                id: stage

                fit: win.fit
                focus: true

                // Enter keeps a preview; Esc closes at once, the preview
                // dropped with it (the user, 2026-11-04: Esc once, not twice).
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.apply();
                        event.accepted = true;
                    }
                }

                // A clear backdrop (only the session dialog dims); a click beside the
                // card closes it.
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }

                Rectangle {
                    id: card

                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(64), Theme.wallpaperWidth)
                    height: body.implicitHeight + Theme.displaysPad * 2
                    radius: Theme.surfaceRadius
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine

                    // Swallows clicks so a near miss does not close the card.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: body

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.displaysPad
                        spacing: Theme.px(14)

                        Item {
                            width: body.width
                            height: title.implicitHeight

                            Text {
                                id: title

                                text: "Wallpaper"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(22)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.previewing ? "Enter applies · Esc closes" : "Esc to close"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(13)
                                color: Theme.surfaceFaint
                            }
                        }

                        Row {
                            spacing: Theme.wallpaperGap

                            Now {
                                tileWidth: Math.floor((body.width - Theme.wallpaperGap) / 2)
                                file: root.deskFile
                                label: "Desktop"
                                targeted: root.target !== "lock"
                            }

                            Now {
                                tileWidth: Math.floor((body.width - Theme.wallpaperGap) / 2)
                                file: root.lockFile
                                label: "Lock screen"
                                targeted: root.target !== "desktop"
                            }
                        }

                        Item {
                            width: body.width
                            height: choices.height

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Apply sets"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuItemTextSize
                                color: Theme.muted
                            }

                            Rectangle {
                                id: choices

                                anchors.right: parent.right
                                width: choiceRow.implicitWidth + Theme.px(6)
                                height: choiceRow.implicitHeight + Theme.px(6)
                                radius: height / 2
                                color: Theme.surfaceWell

                                Row {
                                    id: choiceRow

                                    anchors.centerIn: parent

                                    Choice {
                                        value: "desktop"
                                        label: "Desktop"
                                    }

                                    Choice {
                                        value: "lock"
                                        label: "Lock screen"
                                    }

                                    Choice {
                                        value: "both"
                                        label: "Both"
                                    }
                                }
                            }
                        }

                        // The grid, and beside it how far it scrolls.
                        Item {
                            width: body.width
                            height: grid.height

                            GridView {
                                id: grid

                                // The scroll bar's column, kept whether or not
                                // it shows, so the tiles do not change size.
                                readonly property int barRoom: Theme.px(8) + Theme.px(12)
                                readonly property int tileWidth: Math.floor((body.width - grid.barRoom - Theme.wallpaperGap * (Theme.wallpaperColumns - 1)) / Theme.wallpaperColumns)
                                readonly property int tileHeight: Math.round(grid.tileWidth * 10 / 16)
                                // Rows in view: four, fewer where the screen is short.
                                readonly property int rowsShown: Math.max(1, Math.min(Theme.wallpaperRows,
                                    Math.floor((stage.height - Theme.wallpaperChrome) / grid.cellHeight)))

                                width: body.width - grid.barRoom + Theme.wallpaperGap
                                height: win.choices.length === 0 ? 0
                                        : Math.min(Math.ceil(win.choices.length / Theme.wallpaperColumns), grid.rowsShown)
                                          * grid.cellHeight - Theme.wallpaperGap
                                cellWidth: grid.tileWidth + Theme.wallpaperGap
                                cellHeight: grid.tileHeight + Theme.wallpaperGap
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                // Only the rows in view, and one past them, are built.
                                cacheBuffer: grid.cellHeight
                                model: win.choices

                                delegate: Item {
                                    id: tile

                                    required property var modelData
                                    readonly property bool isPicked: root.candidate === tile.modelData.path
                                    readonly property bool isVideo: root.isVideo(tile.modelData.name)
                                    // A video's first frame, made once (named by the
                                    // file and its time) where no thumbnailer made one.
                                    property string poster: ""
                                    readonly property string posterFile: `${root.posters}/${Qt.md5(tile.modelData.path + tile.modelData.modified)}.png`
                                    // The URI as the thumbnailers write it, each
                                    // segment percent-encoded.
                                    readonly property string cached: {
                                        const uri = "file://" + tile.modelData.path.split("/").map(encodeURIComponent).join("/");
                                        return `file://${root.thumbnails}/${Qt.md5(uri)}.png`;
                                    }

                                    width: grid.tileWidth
                                    height: grid.tileHeight

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.wallpaperRadius + Theme.wallpaperRing
                                        color: tile.isPicked ? Theme.menuHighlight : "transparent"
                                    }

                                    ClippingRectangle {
                                        anchors.fill: parent
                                        anchors.margins: Theme.wallpaperRing
                                        radius: Theme.wallpaperRadius
                                        color: Theme.surfaceWell

                                        // The file manager's thumbnail where it made
                                        // one (the freedesktop cache, named by the
                                        // MD5 of the file's URI): 111 pictures,
                                        // PNGs among them that decode whole, left
                                        // the grid dark for seconds. Else the
                                        // picture, decoded at twice the tile.
                                        Image {
                                            id: thumb

                                            property bool whole: false

                                            anchors.fill: parent
                                            source: !thumb.whole ? tile.cached
                                                  : tile.isVideo ? tile.poster : "file://" + tile.modelData.path
                                            sourceSize.width: grid.tileWidth * 2
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: false
                                            smooth: true
                                            onStatusChanged: {
                                                if (thumb.status === Image.Error && !thumb.whole) {
                                                    thumb.whole = true;
                                                    if (tile.isVideo)
                                                        posterMaker.running = true;
                                                }
                                            }
                                        }

                                        Process {
                                            id: posterMaker

                                            command: ["sh", "-c",
                                                '[ -s "$2" ] || { mkdir -p -- "${2%/*}" && ffmpeg -loglevel error -nostdin -y -i "$1" -frames:v 1 -vf "scale=512:-2" "$2.part.png" && mv -f -- "$2.part.png" "$2"; }',
                                                "sh", tile.modelData.path, tile.posterFile]
                                            onExited: code => {
                                                if (code === 0)
                                                    tile.poster = "file://" + tile.posterFile;
                                            }
                                        }

                                        // A video, as the files a file manager marks.
                                        Rectangle {
                                            visible: tile.isVideo
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.margins: Theme.px(6)
                                            width: Theme.px(22)
                                            height: width
                                            radius: width / 2
                                            color: Qt.rgba(0, 0, 0, 0.55)

                                            Text {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: Theme.px(1)
                                                text: Theme.iconPlay
                                                color: "white"
                                                font.family: Theme.iconFont
                                                font.pixelSize: Theme.px(10)
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: hover.containsMouse
                                            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12)
                                        }
                                    }

                                    MouseArea {
                                        id: hover

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        // A preview, not yet the wallpaper.
                                        onClicked: root.candidate = tile.modelData.path
                                    }
                                }
                            }

                            ScrollTrack {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Theme.px(8)
                                view: grid
                            }
                        }

                        Text {
                            width: body.width
                            visible: win.choices.length === 0
                            wrapMode: Text.Wrap
                            text: pictures.status === FolderListModel.Ready
                                  ? "No pictures here yet: put some in the folder below."
                                  : pictures.status === FolderListModel.Null
                                  ? "~/Pictures/Wallpapers does not exist yet."
                                  : "Reading the folder…"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.menuItemTextSize
                            color: Theme.muted
                        }

                        // The folder at the left; what to do with a preview at the
                        // right, Apply in the accent, both idle until a click.
                        Item {
                            width: body.width
                            height: Theme.controlButtonSize

                            // Pictures are added in the file manager; the grid
                            // follows the folder while it is open.
                            PillButton {
                                id: openFolder

                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                icon: Theme.iconFolderOpen
                                label: "Open folder"
                                onClicked: {
                                    root.close();
                                    Apps.open(["xdg-open", root.folder]);
                                }
                            }

                            // The bar's colours after the wallpaper, in their own
                            // panel (AppearancePanel; the user, 2026-11-11).
                            PillButton {
                                id: colours

                                anchors.left: openFolder.right
                                anchors.leftMargin: Theme.px(8)
                                anchors.verticalCenter: parent.verticalCenter
                                icon: Theme.iconPalette
                                label: "Colours…"
                                onClicked: {
                                    const screen = win.screen;
                                    root.close();
                                    Appearance.togglePanel(screen);
                                }
                            }

                            Text {
                                anchors.left: colours.right
                                anchors.leftMargin: Theme.px(12)
                                anchors.right: actions.left
                                anchors.rightMargin: Theme.px(12)
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideMiddle
                                textFormat: Text.PlainText
                                text: root.status !== "" ? root.status
                                      : root.previewing ? "Previewing: Apply keeps it, Cancel takes it back"
                                      : `~/Pictures/Wallpapers · ${win.choices.length} picture${win.choices.length === 1 ? "" : "s"}`
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuItemTextSize
                                color: root.status !== "" && !setter.running ? Theme.accentRed : Theme.muted
                            }

                            Row {
                                id: actions

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.px(8)

                                PillButton {
                                    label: "Cancel"
                                    usable: root.previewing && !setter.running
                                    onClicked: root.cancel()
                                }

                                PillButton {
                                    label: "Apply"
                                    primary: true
                                    usable: root.previewing && !setter.running
                                    onClicked: root.apply()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
