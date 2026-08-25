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
  readonly property string icalUrlRaw: setting("icalUrl", "")
  readonly property var icalUrls: {
    if (!icalUrlRaw || icalUrlRaw === "") return []
    try {
      var parsed = JSON.parse(icalUrlRaw)
      return Array.isArray(parsed) ? parsed : (parsed ? [parsed] : [])
    } catch(e) {
      return icalUrlRaw ? [icalUrlRaw] : []
    }
  }
  readonly property bool useIcal: !authenticated && icalUrls.length > 0
  readonly property var enabledCals: Model.settingsEnabledCals(setting("enabledCalendars", ""))
  readonly property bool showNextEvent: setting("showNextEvent", true) !== false
  readonly property bool iconOnly: setting("iconOnly", false) === true
  readonly property bool showDate: setting("showDate", false) === true
  readonly property string tooltipMode: setting("tooltipMode", "upcoming") || "upcoming"

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
      var urls = root.icalUrls
      var merged = []
      var pending = urls.length
      function finish() {
        pending--
        if (pending > 0) return
        merged.sort(function(a, b) {
          if (!a.startParsed || !b.startParsed) return 0
          return a.startParsed.getTime() - b.startParsed.getTime()
        })
        root.allEvents = merged
        _updateBar(merged)
      }
      for (var i = 0; i < urls.length; i++) {
        (function(url) {
          Model.fetchIcal(url, function(result) {
            merged = merged.concat(result.events || [])
            finish()
          })
        })(urls[i])
      }
    } else {
      barText = "󰃭"
      barTooltip = "Google Calendar — click to setup"
    }
  }

  function _updateBar(events) {
    if (showDate) {
      var now = new Date()
      var dn = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
      var mn = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
      barText = "󰃭 " + dn[now.getDay()] + " " + now.getDate() + " " + mn[now.getMonth()]
    } else if (showNextEvent && !iconOnly) {
      barText = Model.formatBarLabel(events)
    } else {
      barText = "󰃭"
    }
    barTooltip = Model.formatBarTooltip(events, tooltipMode)
  }

  onShowNextEventChanged: Qt.callLater(function() { _updateBar(root.allEvents) })
  onIconOnlyChanged: Qt.callLater(function() { _updateBar(root.allEvents) })
  onShowDateChanged: Qt.callLater(function() { _updateBar(root.allEvents) })

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
