pragma Singleton

import QtCore
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Singleton {
  id: root
  property int freshMinutes: 5
  property string folderPath: StandardPaths.writableLocation(StandardPaths.DownloadLocation).toString().replace(/^file:\/\//, "")
  property string picturesPath: StandardPaths.writableLocation(StandardPaths.PicturesLocation).toString().replace(/^file:\/\//, "")
  property string videosPath: StandardPaths.writableLocation(StandardPaths.MoviesLocation).toString().replace(/^file:\/\//, "")
  property string fontFamily: Style.font.family
  property var files: []
  property int freshCount: 0
  property int hiddenCount: 0
  property bool scanTruncated: false
  property string scanError: ""
  property string filter: "all"
  property bool showAll: true
  property double now: Date.now()
  property bool open: false
  property string draggingUrl: ""
  property bool pendingRebuild: false
  readonly property int maxRows: 200
  readonly property string displayPath: filter === "images" ? picturesPath : filter === "videos" ? videosPath : folderPath
  function plain(s) { return String(s || "").replace(/[<>]/g, "") }

  function configure(minutes, folder, pictures, videos) {
    var n = Number(minutes)
    if (isFinite(n) && n >= 1 && n <= 1440) freshMinutes = Math.round(n)
    folderPath = folder || decodeURIComponent(StandardPaths.writableLocation(StandardPaths.DownloadLocation).toString().replace(/^file:\/\//, ""))
    picturesPath = pictures || decodeURIComponent(StandardPaths.writableLocation(StandardPaths.PicturesLocation).toString().replace(/^file:\/\//, ""))
    videosPath = videos || decodeURIComponent(StandardPaths.writableLocation(StandardPaths.MoviesLocation).toString().replace(/^file:\/\//, ""))
  }
  function fileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }
  function show() { showOn(null, null, null) }
  function hide() { open = false }
  function toggle() { open ? hide() : show() }
  function showOn(anchor, bar, owner) {
    filter = "all"
    if (anchor) { win.anchorItem = anchor; win.bar = bar; win.owner = owner || null }
    now = Date.now()
    open = true
    rebuild()
  }
  function sourceFolder(source) {
    if (source === "downloads") return folderPath
    if (source === "images") return picturesPath
    if (source === "videos") return videosPath
    return ""
  }
  function openSourceFolder(source) {
    var path = sourceFolder(source)
    if (!path.startsWith("/")) return false
    Quickshell.execDetached(["xdg-open", path])
    hide()
    return true
  }
  function openFolder() {
    if (displayPath.startsWith("/")) Quickshell.execDetached(["xdg-open", displayPath])
  }

  function rebuild() {
    if (draggingUrl !== "") { pendingRebuild = true; return }
    pendingRebuild = false
    var seen = {}
    var merged = []
    var fresh = 0
    var cutoff = now - freshMinutes * 60000
    var input = downloads.files.concat(pictures.files, videos.files)
    for (var i = 0; i < input.length; i++) {
      var f = input[i]
      if (seen[f.path]) continue
      seen[f.path] = true
      var isFresh = f.modified >= cutoff
      if (isFresh) fresh++
      if (!showAll && !isFresh) continue
      if (filter === "downloads" && f.source !== "downloads") continue
      if ((filter === "images" || filter === "videos") && f.category !== filter) continue
      merged.push(Object.assign({}, f, {url: fileUrl(f.path), fresh: isFresh}))
    }
    merged.sort(function(a, b) { return b.modified - a.modified || a.path.localeCompare(b.path) })
    hiddenCount = Math.max(0, merged.length - maxRows) + downloads.hidden + pictures.hidden + videos.hidden
    scanTruncated = downloads.truncated || pictures.truncated || videos.truncated
    scanError = [downloads.error ? "Downloads: " + downloads.error : "", pictures.error ? "Pictures: " + pictures.error : "", videos.error ? "Videos: " + videos.error : ""].filter(function(s) { return s !== "" }).join(" · ")
    freshCount = fresh
    var next = merged.slice(0, maxRows)
    if (JSON.stringify(next) !== JSON.stringify(files)) files = next
  }
  onFilterChanged: rebuild()
  onShowAllChanged: rebuild()
  onDraggingUrlChanged: if (draggingUrl === "" && pendingRebuild) rebuild()
  onFreshMinutesChanged: rebuild()

  FolderSource {
    id: downloads; path: root.folderPath; kind: "downloads"; panelOpen: root.open
    onFilesChanged: root.rebuild()
    onHiddenChanged: root.rebuild()
    onTruncatedChanged: root.rebuild()
    onErrorChanged: root.rebuild()
  }
  FolderSource {
    id: pictures; path: root.picturesPath; kind: "images"; panelOpen: root.open
    onFilesChanged: root.rebuild()
    onHiddenChanged: root.rebuild()
    onTruncatedChanged: root.rebuild()
    onErrorChanged: root.rebuild()
  }
  FolderSource {
    id: videos; path: root.videosPath; kind: "videos"; panelOpen: root.open
    onFilesChanged: root.rebuild()
    onHiddenChanged: root.rebuild()
    onTruncatedChanged: root.rebuild()
    onErrorChanged: root.rebuild()
  }
  Timer { interval: 20000; running: true; repeat: true; onTriggered: { root.now = Date.now(); root.rebuild() } }

  // One thumbnail process at a time, requested only by instantiated video rows.
  // Cache results separately so a completed thumbnail never recreates the list.
  property var previews: ({})
  property var previewQueue: []
  property string previewKey: ""
  function requestPreview(file) {
    if (!file || file.category !== "videos" || !file.path) return
    var key = file.path + ":" + file.version
    if (previews[key] !== undefined || previewKey === key) return
    for (var i = 0; i < previewQueue.length; i++) if (previewQueue[i].key === key) return
    previewQueue.push({key: key, path: file.path})
    previewNext.restart()
  }
  Timer {
    id: previewNext; interval: 1
    onTriggered: {
      if (thumbnailProc.running || !root.open || root.previewQueue.length === 0) return
      var item = root.previewQueue.shift()
      root.previewKey = item.key
      thumbnailProc.command = [decodeURIComponent(Qt.resolvedUrl("bin/thumbnail").toString().replace(/^file:\/\//, "")), item.path]
      thumbnailProc.running = true
    }
  }
  onOpenChanged: {
    if (open) previewNext.restart()
    else previewQueue = []
  }
  Process {
    id: thumbnailProc
    stdout: StdioCollector {
      onStreamFinished: {
        var result = {}
        try { result = JSON.parse(text) } catch (e) {}
        var next = Object.assign({}, root.previews)
        next[root.previewKey] = result
        root.previews = next
      }
    }
    onExited: { root.previewKey = ""; previewNext.restart() }
  }
  readonly property string iconDownload: "\uF019"
  readonly property string iconFolder: "\uF07C"
  readonly property string iconFile: "\uF15B"
  readonly property string iconImage: "\uF1C5"
  readonly property string iconPdf: "\uF1C1"
  readonly property string iconArchive: "\uF1C6"
  readonly property string iconAudio: "\uF1C7"
  readonly property string iconVideo: "\uF1C8"
  readonly property string iconCode: "\uF1C9"
  readonly property string iconText: "\uF0F6"

  function suffixOf(name) {
    var m = /\.([A-Za-z0-9]+)$/.exec(String(name))
    return m ? m[1].toLowerCase() : ""
  }

  function iconFor(name, isDir) {
    if (isDir) return root.iconFolder
    var s = root.suffixOf(name)
    if (/^(png|jpg|jpeg|gif|webp|bmp|svg|avif|heic|ico|tiff?)$/.test(s)) return root.iconImage
    if (s === "pdf") return root.iconPdf
    if (/^(zip|tar|gz|tgz|bz2|xz|7z|rar|zst|deb|rpm|pkg|iso|img|dmg|appimage)$/.test(s)) return root.iconArchive
    if (/^(mp3|wav|flac|ogg|m4a|aac|opus|wma)$/.test(s)) return root.iconAudio
    if (/^(mp4|mkv|mov|avi|webm|m4v|mpg|mpeg|wmv)$/.test(s)) return root.iconVideo
    if (/^(js|ts|json|py|rb|sh|c|h|cpp|rs|go|java|qml|html|css|xml|yml|yaml|toml)$/.test(s)) return root.iconCode
    if (/^(txt|md|csv|log|rtf|doc|docx|odt|xls|xlsx|ods|ppt|pptx|odp|epub)$/.test(s)) return root.iconText
    return root.iconFile
  }

  function formatSize(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n < 0) return ""
    if (n < 1024) return n + " B"
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB"
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(n < 10 * 1024 * 1024 ? 1 : 0) + " MB"
    return (n / (1024 * 1024 * 1024)).toFixed(1) + " GB"
  }

  function formatAge(ms) {
    var secs = Math.max(0, Math.round((root.now - ms) / 1000))
    if (secs < 45) return "just now"
    var mins = Math.round(secs / 60)
    if (mins < 60) return mins + " min"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + " h"
    var days = Math.floor(hours / 24)
    if (days < 7) return days + " d"
    var weeks = Math.floor(days / 7)
    if (weeks < 5) return weeks + " w"
    return Math.floor(days / 30) + " mo"
  }

  DownloadsPopup {
    id: win

    open: root.open
    dragging: root.draggingUrl !== ""
    contentWidth: Style.space(520)

    // The height follows the list instead of being a fixed box: with two
    // downloads in it, a 560px window is mostly empty, which reads as a
    // window rather than as a popout. Computed from the row count rather
    // than from the ListView's contentHeight, so nothing depends on a child
    // that in turn depends on this.
    readonly property int rowStride: Style.space(34) + Style.space(2)
    readonly property int chromeHeight: Style.space(144)
    readonly property int listHeight: Math.min(Style.space(420),
      Math.max(Style.space(64), root.files.length * rowStride))
    contentHeight: chromeHeight + listHeight

    onDismissed: root.hide()

    FocusScope {
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.hide()

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(10)

        // Header: what this is, what is being shown, and a way into the folder.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: root.iconDownload
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
            renderType: Text.NativeRendering
            color: root.freshCount > 0 ? Color.accent : Color.foreground
          }

          Text {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: "Recent files"
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            renderType: Text.NativeRendering
            color: Color.foreground
          }

          Button {
            Layout.alignment: Qt.AlignVCenter
            iconText: root.iconFolder
            tooltipText: root.plain("Open " + root.displayPath)
            foreground: Color.muted
            accent: Color.accent
            fontFamily: root.fontFamily
            iconSize: Style.font.iconSmall
            onClicked: root.openFolder()
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)
          Row {
            spacing: Style.spacing.md
            Repeater {
              model: [
                { value: "all", label: "All" },
                { value: "downloads", label: "Downloads" },
                { value: "images", label: "Images" },
                { value: "videos", label: "Videos" }
              ]
              delegate: Button {
                required property var modelData
                text: modelData.label
                selected: root.filter === modelData.value
                bordered: true
                foreground: Color.foreground
                background: Color.background
                accent: Color.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                focusable: false
                onClicked: root.filter = modelData.value
                onRightClicked: {
                  if (!root.openSourceFolder(modelData.value)) noFolder.restart()
                }
                // Translate just the painted button, leaving its layout slot
                // and its neighbours fixed. All has no single folder to open.
                transform: Translate { id: nudge }
                SequentialAnimation {
                  id: noFolder
                  NumberAnimation { target: nudge; property: "x"; from: 0; to: -Style.space(2); duration: 40 }
                  NumberAnimation { target: nudge; property: "x"; to: Style.space(2); duration: 60 }
                  NumberAnimation { target: nudge; property: "x"; to: 0; duration: 50 }
                }
              }
            }
          }
          Item { Layout.fillWidth: true }
          // Reuse the shell's themed controls for the time and source filters.
          ButtonGroup {
            Layout.alignment: Qt.AlignVCenter
            options: [
              { value: "fresh", label: root.freshMinutes + " minutes" },
              { value: "all", label: "All time" }
            ]
            value: root.showAll ? "all" : "fresh"
            foreground: Color.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            // The window has no panel cursor to hand around, so the group is
            // mouse-only and stays out of the Tab order.
            focusable: false
            onChanged: function(v) { root.showAll = (v === "all") }
          }

        }

        Rectangle {
          Layout.fillWidth: true
          height: Style.spacing.hairline
          color: Color.popups.border
        }

        // The list. Each row is a drag handle; see DownloadRow.qml.
        ListView {
          id: list
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: 0
          visible: root.files.length > 0
          clip: true
          spacing: Style.space(2)
          model: root.open ? root.files : []
          cacheBuffer: 0
          boundsBehavior: Flickable.StopAtBounds

          delegate: DownloadRow {
            required property var modelData
            width: list.width
            store: root
            // A delegate outlives the row it was built for by a moment when
            // the model is replaced, and reads modelData once more on the way
            // out. Without the fallback that read is undefined, file.url
            // throws inside the binding, and the whole binding resolves to
            // undefined rather than to a value the property can hold.
            file: modelData || ({})
          }
        }

        // Empty state, which is the normal state for the "last N min" filter.
        Text {
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: root.files.length === 0
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.showAll ? "No files in this view" : "No files in the last " + root.freshMinutes + " minutes."
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
          color: Color.muted
        }

        Text {
          Layout.fillWidth: true
          visible: root.hiddenCount > 0 || root.scanTruncated || root.scanError !== ""
          wrapMode: Text.WordWrap
          text: root.scanError || (root.scanTruncated
            ? "Large folder: showing a limited scan. Open the folder for all files."
            : "+ " + root.hiddenCount + " more files not shown")
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Color.muted
        }

        Text {
          Layout.fillWidth: true
          visible: root.files.length > 0
          textFormat: Text.PlainText
          text: "Drag a row into any window to hand over the file."
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Color.muted
        }
      }
    }
  }
}
