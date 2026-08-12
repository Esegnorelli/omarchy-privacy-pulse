import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "esegnorelli.privacy-pulse"
  ipcTarget: "esegnorelli.privacy-pulse"

  property var scan: Model.emptyState()
  property var rows: []
  property int rowIndex: 0
  property bool cursorActive: false
  property bool scanFailed: false

  readonly property string scriptPath: String(Qt.resolvedUrl("privacy_scan.py")).replace(/^file:\/\//, "")
  readonly property bool isActive: !!(scan && scan.active)
  readonly property string barIcon: Model.barLabel(scan)
  readonly property string barTip: Model.tooltip(scan)

  function refresh() {
    if (!scanProc.running)
      scanProc.running = true
  }

  function applyScan(raw) {
    var parsed = Model.parseScan(raw)
    scan = parsed
    rows = Model.flattenRows(parsed)
    scanFailed = parsed.ok === false
    if (rowIndex >= rows.length)
      rowIndex = Math.max(0, rows.length - 1)
  }

  function selectByDelta(delta) {
    if (!rows.length) {
      rowIndex = 0
      return
    }
    rowIndex = Math.max(0, Math.min(rows.length - 1, rowIndex + delta))
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
      rowIndex = 0
    }
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: scanProc
    command: ["python3", root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.scanFailed = true
    }
  }

  // Keep the bar honest while the panel is closed; poll a bit faster when open.
  Timer {
    interval: root.opened ? 1500 : 2500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    active: root.isActive
    fixedWidth: root.bar && root.bar.vertical ? -1 : (root.isActive ? -1 : Style.space(27))
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    horizontalMargin: root.isActive ? 6.5 : 8.5
    tooltipText: root.barTip
    onPressed: function(b) {
      if (b === Qt.MiddleButton || b === Qt.RightButton)
        root.refresh()
      else
        root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0)
          root.selectByDelta(dy)
        else if (dx !== 0)
          root.selectByDelta(dx)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            text: "Privacy Pulse"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            text: root.isActive
              ? (root.scan.counts.total + " active capture" + (root.scan.counts.total === 1 ? "" : "s"))
              : (root.scanFailed ? "Scanner error — middle-click to retry" : "Sensors clear")
            color: root.isActive
              ? (root.bar ? root.bar.urgent : Color.urgent)
              : root.bar.foreground
            opacity: root.isActive ? 1 : 0.72
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.rows

            delegate: Item {
              required property var modelData
              required property int index
              width: parent.width
              height: rowBox.implicitHeight

              readonly property bool isHeader: modelData.type === "header"
              readonly property bool isEmpty: modelData.type === "empty"
              readonly property bool selected: root.cursorActive && root.rowIndex === index

              BorderSurface {
                id: rowBox
                width: parent.width
                implicitHeight: inner.implicitHeight + Style.space(isHeader ? 6 : 12)
                radius: Style.cornerRadius
                color: {
                  if (isHeader) return "transparent"
                  if (selected)
                    return Style.selectedFillFor(root.bar.foreground, Color.accent)
                  return mouseArea.containsMouse
                    ? Style.hoverFillFor(root.bar.foreground, Color.accent)
                    : "transparent"
                }
                borderSpec: selected && !isHeader
                  ? Border.controlSpec("focus", root.bar.foreground, Color.accent)
                  : Border.none()

                Column {
                  id: inner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(2)

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      text: isHeader || isEmpty
                        ? (modelData.icon || (isEmpty ? "󰔓" : "•"))
                        : Model.sectionIcon(modelData.kind)
                      color: root.isActive && !isEmpty
                        ? (root.bar ? root.bar.urgent : Color.urgent)
                        : root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: isHeader ? Style.font.bodySmall : Style.font.body
                      opacity: isHeader ? 0.7 : 1
                    }

                    Text {
                      width: parent.width - parent.spacing - 28
                      text: isHeader
                        ? modelData.title
                        : (isEmpty ? modelData.title : modelData.app)
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: isHeader ? Style.font.bodySmall : Style.font.body
                      font.bold: isHeader || !isEmpty
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    visible: !isHeader && !!(isEmpty ? modelData.detail : modelData.detail)
                    width: parent.width
                    leftPadding: Style.space(28)
                    text: isEmpty
                      ? modelData.detail
                      : (modelData.detail + (modelData.pid != null ? "  ·  pid " + modelData.pid : ""))
                    color: root.bar.foreground
                    opacity: 0.68
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                  }
                }

                MouseArea {
                  id: mouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !isHeader
                  onEntered: {
                    root.cursorActive = true
                    root.rowIndex = index
                  }
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "Polls PipeWire + /dev/video · middle-click refresh"
          color: root.bar.foreground
          opacity: 0.45
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
