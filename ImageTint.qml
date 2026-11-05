import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// Latest source wins: at most one decoder per buffer and no request queue.
Rectangle {
  id: tint
  property url source: ""
  property string requested: ""
  color: Commons.Color.popups.background
  Behavior on color { ColorAnimation { duration: 90 } }

  function refresh() {
    if (reader.running) return
    if (!String(source)) { color = Commons.Color.popups.background; return }
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
          tint.color = result.color || Commons.Color.popups.background
        } catch (e) { tint.color = Commons.Color.popups.background }
      }
    }
    onExited: if (String(tint.source) !== tint.requested) Qt.callLater(tint.refresh)
  }
}
