import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io

// Keep expensive scans outside the shell. Only small folders get a live
// FolderListModel watcher; large folders are polled and scans are bounded.
Item {
  id: source
  property string path: ""
  property string kind: "downloads"
  property bool panelOpen: false
  property var files: []
  property int hidden: 0
  property bool truncated: false
  property string error: ""
  property url watchedFolder: ""
  property bool pending: false
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/downloads").toString().replace(/^file:\/\//, ""))

  function refresh() {
    if (!path) return
    if (reader.running) { pending = true; return }
    pending = false
    reader.requestPath = source.path
    reader.requestKind = source.kind
    reader.command = [source.helper, "list", source.path, source.kind]
    reader.running = true
  }
  onPathChanged: { watchedFolder = ""; coalesce.restart() }
  onKindChanged: coalesce.restart()
  onPanelOpenChanged: if (panelOpen) refresh()
  Component.onCompleted: coalesce.restart()
  Timer { id: coalesce; interval: 250; onTriggered: source.refresh() }
  Timer {
    interval: source.panelOpen ? 3000 : 20000
    running: true; repeat: true
    onTriggered: source.refresh()
  }
  Process {
    id: reader
    property string requestPath: ""
    property string requestKind: ""
    stdout: StdioCollector {
      onStreamFinished: {
        if (reader.requestPath !== source.path || reader.requestKind !== source.kind) { source.pending = true; return }
        try {
          var data = JSON.parse(text)
          source.error = data.ok ? "" : String(data.error || "Folder unavailable")
          var next = data.files || []
          // Avoid rebuilding delegates (and interrupting hover/drag) on ticks.
          if (JSON.stringify(next) !== JSON.stringify(source.files)) source.files = next
          source.hidden = data.hidden || 0
          source.truncated = data.truncated === true
          source.watchedFolder = data.ok && data.scanned < 2000
            ? "file://" + source.path.split("/").map(encodeURIComponent).join("/") : ""
        } catch (e) { source.error = "Could not read folder" }
      }
    }
    onExited: if (source.pending) coalesce.restart()
  }
  FolderListModel {
    id: watcher
    folder: source.watchedFolder
    showDirs: true; showHidden: false; showDotAndDotDot: false
    sortField: FolderListModel.Unsorted
    onCountChanged: coalesce.restart()
    onStatusChanged: if (status === FolderListModel.Ready) coalesce.restart()
  }
}
