import QtQuick
import QtMultimedia
import qs.Commons

// One player for the hovered file. Changing source stops the previous decoder;
// leaving/closing the panel pauses or destroys it, and audio stays muted.
Item {
  id: root
  property url source: ""
  property url poster: ""
  property bool playing: false
  property bool frameReady: false
  property bool initialized: false
  readonly property bool failed: player.error !== MediaPlayer.NoError

  function loadSource() {
    if (String(player.source) === String(source)) {
      if (playing && String(source) !== "") player.play()
      else player.pause()
      return
    }
    player.stop()
    output.clearOutput()
    frameReady = false
    player.source = source
    if (playing && String(source) !== "") player.play()
  }
  onSourceChanged: {
    if (!initialized) return
    player.pause()
    frameReady = false
    // Collapse same-turn source changes and always read the latest binding.
    Qt.callLater(root.loadSource)
  }
  onPlayingChanged: {
    if (!initialized) return
    if (playing) Qt.callLater(root.loadSource)
    else player.pause()
  }
  Component.onCompleted: { initialized = true; loadSource() }
  Component.onDestruction: player.stop()

  ImageTint { anchors.fill: parent; source: root.poster }
  Image {
    anchors.fill: parent
    source: root.poster
    sourceSize: Qt.size(1600, 1600)
    asynchronous: true
    fillMode: Image.PreserveAspectFit
  }
  VideoOutput {
    id: output
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectFit
    endOfStreamPolicy: VideoOutput.KeepLastFrame
    opacity: root.frameReady && !root.failed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 90 } }
  }
  MediaPlayer {
    id: player
    videoOutput: output
    audioOutput: AudioOutput { muted: true; volume: 0 }
    loops: MediaPlayer.Infinite
  }
  Connections {
    target: output.videoSink
    function onVideoFrameChanged() {
      if (player.playbackState === MediaPlayer.PlayingState && output.videoSink.videoSize.width > 0)
        root.frameReady = true
    }
  }
  Text {
    anchors.centerIn: parent
    visible: root.failed
    text: "Preview unavailable · Double-click to open"
    textFormat: Text.PlainText
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: Color.foreground
    style: Text.Outline
    styleColor: Color.background
  }
}
