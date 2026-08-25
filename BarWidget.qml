import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "OAuth.js" as OAuth

BarWidget {
  id: root
  moduleName: "io.github.fullo.gcal"

  property var allEvents: []
  property string barText: "󰃭"
  property string barTooltip: "Google Calendar"

  readonly property bool authenticated: OAuth.isAuthenticated(root.settings)
  readonly property bool useIcal: !authenticated && setting("icalUrl", "") !== ""
  readonly property var enabledCals: Model.settingsEnabledCals(setting("enabledCalendars", ""))
  readonly property bool showNextEvent: setting("showNextEvent", true) !== false
  readonly property bool iconOnly: setting("iconOnly", false) === true

  function refresh() {
    if (authenticated) {
      OAuth.getValidToken(root.settings, function(ok, token) {
        if (!ok) {
          barText = "󰃭"
          barTooltip = "Calendar — OAuth expired"
          return
        }
        Model.fetchGoogleAgenda(token, enabledCals, function(events) {
          root.allEvents = events
          _updateBar(events)
        })
      })
    } else if (useIcal) {
      var url = setting("icalUrl", "")
      Model.fetchIcal(url, function(events) {
        root.allEvents = events
        _updateBar(events)
      })
    } else {
      barText = "󰃭"
      barTooltip = "Google Calendar — click to setup"
    }
  }

  function _updateBar(events) {
    if (iconOnly || !showNextEvent) {
      barText = "󰃭"
    } else {
      barText = Model.formatBarLabel(events)
    }
    barTooltip = Model.formatBarTooltip(events)
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

  visible: true
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
    hasVisualContent: true
    tooltipText: root.barTooltip
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.togglePanel()
    }
  }
}
