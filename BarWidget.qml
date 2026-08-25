import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.fullo.gcal"

  property var allEvents: []
  property string barText: ""
  property string barTooltip: ""

  readonly property var enabledCals: Model.settingsEnabledCals(setting("enabledCalendars", ""))

  function refresh() {
    if (!agendaProc.running) agendaProc.running = true
  }

  function buildGcalcliArgs() {
    var args = ["gcalcli", "--tsv", "--nocolor", "agenda"]
    var cals = root.enabledCals
    if (cals) {
      for (var i = 0; i < cals.length; i++) args.push("--cal", cals[i])
    }
    return args
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  visible: barText !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  IpcHandler {
    target: "io.github.fullo.gcal"
    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  Process {
    id: agendaProc
    command: root.buildGcalcliArgs()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        root.allEvents = raw ? Model.parseTsvAgenda(raw) : []
        root.barText = Model.formatBarLabel(root.allEvents)
        root.barTooltip = Model.formatBarTooltip(root.allEvents)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.allEvents = []
        root.barText = ""
        root.barTooltip = "gcalcli error"
      }
    }
  }

  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    labelVisible: true
    hasVisualContent: root.barText !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.togglePanel()
    }

    ToolTip {
      visible: button.containsMouse && root.barTooltip !== ""
      text: root.barTooltip
      delay: 600
    }
  }
}
