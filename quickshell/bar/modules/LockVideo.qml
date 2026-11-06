import QtQuick
import QtQuick.Effects
import QtMultimedia

// A video wallpaper under the lock screen (LockScreen loads this only when
// lock-spec.py names one; the user, 2026-11-05): played muted and looping,
// blurred and saturated as the picture is, from a copy a fraction of the
// screen's size, which is all a heavy blur leaves anyway. It starts on its
// first frame, which is the picture LockScreen shows under it (wallpaper.sh
// stores that frame), and fades over it once frames are coming, so it takes
// over without a jump. Its own file so QtMultimedia loads only when a video
// is set; it goes with the lock's process at the unlock, decoder and all.
Item {
    id: root

    required property string source
    property size textureSize: Qt.size(640, 400)
    property bool blurOn: false
    property real blurMax: 1
    property real saturation: 0

    // Frames on the screen, not only a file opened.
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState && player.position > 0

    MediaPlayer {
        id: player

        source: root.source
        loops: MediaPlayer.Infinite
        videoOutput: output

        Component.onCompleted: player.play()
        onErrorOccurred: (error, message) => console.warn("[lock] the video does not play:", message)
    }

    VideoOutput {
        id: output

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    ShaderEffectSource {
        id: small

        anchors.fill: parent
        sourceItem: output
        hideSource: true
        live: true
        textureSize: root.textureSize
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: small
        autoPaddingEnabled: false
        blurEnabled: root.blurOn
        blurMax: root.blurMax
        blur: 1.0
        saturation: root.saturation
        opacity: root.playing ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }
}
