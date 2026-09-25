import QtQuick
import Quickshell.Io
import qs.Commons

// Latest source wins: at most one decoder per buffer and no request queue.
Rectangle {
  id: tint
  property url source: ""
  property string requested: ""
  color: Color.popups.background
  Behavior on color { ColorAnimation { duration: 90 } }

  function refresh() {
    if (reader.running) return
    if (!String(source)) { color = Color.popups.background; return }
    requested = String(source)
    reader.command = [decodeURIComponent(Qt.resolvedUrl("bin/image-color").toString().replace(/^file:\/\//, "")), requested]
    reader.running = true
  }
  onSourceChanged: refresh()
  Process {
    id: reader
    stdout: StdioCollector {
      onStreamFinished: {
        if (String(tint.source) !== tint.requested) return
        try {
          var result = JSON.parse(text)
          tint.color = result.color || Color.popups.background
        } catch (e) { tint.color = Color.popups.background }
      }
    }
    onExited: if (String(tint.source) !== tint.requested) Qt.callLater(tint.refresh)
  }
}
