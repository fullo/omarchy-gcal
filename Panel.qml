import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "OAuth.js" as OAuth

Panel {
  id: root
  moduleName: "io.github.fullo.gcal"
  ipcTarget: "io.github.fullo.gcal"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Data
  property var allEvents: []
  property var todayEvents: []
  property var weekEvents: []
  property var eventGroups: []
  property var calendars: []
  property string fetchError: ""

  // Settings
  readonly property bool showNextEvent: setting("showNextEvent", true) !== false
  readonly property bool iconOnly: setting("iconOnly", false) === true
  readonly property bool showDate: setting("showDate", false) === true
  readonly property string tooltipMode: setting("tooltipMode", "upcoming") || "upcoming"

  // Auth state
  property bool authenticating: false
  property string authCodeInput: ""
  property string authStatus: ""
  property bool showAdvanced: false

  // iCal state
  property string icalInput: ""
  property bool icalConnecting: false

  // Mode: "ical" (default) or "oauth"
  readonly property bool useOAuth: OAuth.isAuthenticated(root.settings)
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
  readonly property bool useIcal: !useOAuth && icalUrls.length > 0

  // View state
  property int activeTab: 0
  property int viewYear: new Date().getFullYear()
  property int viewMonth: new Date().getMonth()
  readonly property string todayKey: Model.dateKeyFromDate(new Date())
  property int monthEventsPage: 0
  readonly property int monthEventsPerPage: 5

  // Calendar filter
  readonly property var enabledCals: Model.settingsEnabledCals(setting("enabledCalendars", ""))

  // Styling
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int cellWidth: Style.space(42)
  readonly property int cellHeight: Style.space(30)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(28)
  readonly property var weekdays: Model.weekdayOrder(1)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, 1, todayKey)

  function eventsOnDay(dayKey) {
    var count = 0
    for (var i = 0; i < allEvents.length; i++) {
      if (allEvents[i].date === dayKey) count++
    }
    return count
  }

  function open() {
    root.controller.show()
    refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    if (useOAuth) {
      // Google Calendar API via OAuth
      OAuth.getValidToken(root.settings, function(ok, token) {
        if (!ok) {
          root.fetchError = "OAuth expired — reconnect in Setup"
          return
        }
        fetchError = ""
        Model.fetchGoogleAgenda(token, enabledCals, function(events) {
          root.allEvents = events
          root.todayEvents = Model.eventsForToday(events)
          root.weekEvents = Model.eventsForThisWeek(events)
          root.eventGroups = Model.groupEventsByDay(root.weekEvents)
          if (events.length === 0) root.fetchError = "No upcoming events"
        })
        Model.fetchGoogleCalendars(token, function(cals) {
          root.calendars = cals
        })
      })
    } else if (useIcal) {
      // iCal feeds (read-only, multiple)
      var urls = root.icalUrls
      var allCalEvents = []
      var pending = urls.length
      var calsList = []
      function finishIcal() {
        pending--
        if (pending > 0) return
        allCalEvents.sort(function(a, b) {
          if (!a.startParsed || !b.startParsed) return 0
          return a.startParsed.getTime() - b.startParsed.getTime()
        })
        root.fetchError = ""
        root.allEvents = allCalEvents
        root.todayEvents = Model.eventsForToday(allCalEvents)
        root.weekEvents = Model.eventsForThisWeek(allCalEvents)
        root.eventGroups = Model.groupEventsByDay(root.weekEvents)
        root.calendars = calsList
        if (allCalEvents.length === 0) root.fetchError = "No upcoming events"
      }
      var icalColors = ["#2196f3", "#e91e63", "#4caf50", "#ff9800", "#9c27b0", "#00bcd4"]
      for (var ui = 0; ui < urls.length; ui++) {
        (function(url, idx) {
          var feedName = url.match(/\/ical\/([^/]+)\//)
          var fallbackName = feedName ? decodeURIComponent(feedName[1]) : "iCal Feed " + (idx + 1)
          calsList.push({ id: "ical-" + idx, name: fallbackName, access: "read-only", color: icalColors[idx % icalColors.length] })
          Model.fetchIcal(url, function(result) {
            var events = result.events || []
            var extractedName = result.calName || ""
            if (extractedName) calsList[idx].name = extractedName
            for (var ei = 0; ei < events.length; ei++) events[ei].calendar = "ical-" + idx
            allCalEvents = allCalEvents.concat(events)
            finishIcal()
          })
        })(urls[ui], ui)
      }
    } else {
      root.fetchError = "Add an iCal URL or connect Google Calendar in Setup"
    }
  }

  function openEvent(link) {
    if (link && link !== "") Qt.openUrlExternally(link)
  }

  function setTab(idx) {
    root.activeTab = idx
    if (idx === 2) Qt.callLater(root.autoPageToToday)
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
    root.monthEventsPage = 0
    Qt.callLater(scrollToToday)
  }

  function goToToday() {
    var now = new Date()
    root.viewYear = now.getFullYear()
    root.viewMonth = now.getMonth()
    root.monthEventsPage = 0
    Qt.callLater(scrollToToday)
  }

  function scrollToToday() {
    var sw = typeof monthScroll !== "undefined" ? monthScroll : null
    if (!sw) return
    var now = new Date()
    if (now.getMonth() !== root.viewMonth || now.getFullYear() !== root.viewYear) {
      sw.contentY = 0
      return
    }
    var today = Model.dateKeyFromDate(now)
    var weekH = root.cellHeight + Style.space(2)
    var rows = root.weeks
    for (var i = 0; i < rows.length; i++) {
      var days = rows[i].days
      for (var j = 0; j < days.length; j++) {
        if (days[j].key === today) {
          sw.contentY = Math.max(0, i * weekH - (sw.height - weekH) / 2)
          return
        }
      }
    }
  }

  function monthEventsForView() {
    var prefix = root.viewYear + "-" + Model.pad2(root.viewMonth + 1) + "-"
    var filtered = []
    for (var i = 0; i < allEvents.length; i++) {
      if (allEvents[i].date && allEvents[i].date.indexOf(prefix) === 0)
        filtered.push(allEvents[i])
    }
    filtered.sort(function(a, b) {
      if (a.date < b.date) return -1
      if (a.date > b.date) return 1
      if (!a.startTime && b.startTime) return -1
      if (a.startTime && !b.startTime) return 1
      if (a.startTime && b.startTime) return a.startTime < b.startTime ? -1 : 1
      return 0
    })
    return filtered
  }

  function autoPageToToday() {
    var events = monthEventsForView()
    var today = Model.dateKeyFromDate(new Date())
    for (var j = 0; j < events.length; j++) {
      if (events[j].date >= today) {
        root.monthEventsPage = Math.floor(j / root.monthEventsPerPage)
        return
      }
    }
    root.monthEventsPage = Math.max(0, Math.ceil(events.length / root.monthEventsPerPage) - 1)
  }

  // ---- OAuth ----

  function startAuth() {
    authenticating = true
    authStatus = "Opening browser..."
    authCodeInput = ""
    Qt.openUrlExternally(OAuth.authUrl(root.settings))
  }

  function submitAuthCode() {
    if (authCodeInput.trim() === "") {
      authStatus = "Paste the URL from the browser"
      return
    }
    authStatus = "Connecting..."
    OAuth.exchangeCode(root.settings, authCodeInput.trim(), function(ok, result) {
      authenticating = false
      if (ok) {
        _updateSettings({
          access_token: result.access_token,
          refresh_token: result.refresh_token,
          expires_at: result.expires_at
        })
        authStatus = "Connected!"
        authCodeInput = ""
        refresh()
      } else {
        authStatus = result || "Connection failed"
      }
    })
  }

  function _updateSettings(patch) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var p in patch) entry[p] = patch[p]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Timer ----

  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---- Panel UI ----

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.activeTab === 2) root.moveMonth(dx)
      }
      onTextKey: function(t) {
        if (t === "1") root.setTab(0)
        else if (t === "2") root.setTab(1)
        else if (t === "3") root.setTab(2)
        else if (t === "4") root.setTab(3)
        else if (t === "5") root.setTab(4)
        else if (t === "t" || t === "T") root.goToToday()
        else if (root.activeTab === 2) {
          if (t === "[") root.moveMonth(-1)
          else if (t === "]") root.moveMonth(1)
        }
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroll.width
          spacing: Style.space(10)

          // ---- Hero ----
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰃭"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 32
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Google Calendar"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 24
                font.bold: true
              }
            }
          }

          // ---- Tab bar ----
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)

            Repeater {
              model: ["Today", "Week", "Month", "Calendars", "Setup"]

              Rectangle {
                required property string modelData
                required property int index
                width: tabLabel.implicitWidth + Style.space(20)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.activeTab === index
                  ? Style.selectedStateColor(root.contentForeground, Color.accent)
                  : (tabMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent")

                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  text: modelData
                  color: root.activeTab === index
                    ? Style.hoverStateColor(root.contentForeground, Color.accent)
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: root.activeTab === index
                }

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setTab(index)
                }
              }
            }
          }

          // Hairline
          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.contentForeground
            opacity: 0.12
          }

          // ---- Error / loading ----
          Text {
            visible: root.fetchError !== ""
            width: parent.width
            text: root.fetchError
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
            horizontalAlignment: Text.AlignHCenter
          }

          // ================================================================
          //  TAB 0: TODAY
          // ================================================================
          Column {
            visible: root.activeTab === 0
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: Qt.formatDate(new Date(), "ddd d MMMM").toUpperCase()
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Repeater {
              model: root.todayEvents

              Rectangle {
                required property var modelData
                width: parent.width
                height: evRow.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: evMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                opacity: Model.isEventPast(modelData) ? 0.4 : 1.0

                Row {
                  id: evRow
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Rectangle {
                    width: Style.space(6)
                    height: Style.space(6)
                    radius: Style.space(3)
                    color: Model.eventCalendarColor(modelData, root.calendars)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    width: Style.space(80)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      text: Model.isAllDayEvent(modelData) ? "All day" : Model.formatEventTime(modelData)
                      color: evMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  Rectangle {
                    width: Style.spacing.hairline
                    height: evDetails.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.contentForeground
                    opacity: 0.15
                  }

                  Column {
                    id: evDetails
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(80) - Style.space(8) - Style.spacing.hairline - Style.space(8)
                    Text {
                      width: parent.width
                      text: modelData.title || "(No title)"
                      color: evMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      visible: modelData.location !== ""
                      width: parent.width
                      text: "󰍹 " + modelData.location
                      color: Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                MouseArea {
                  id: evMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: modelData.link !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.openEvent(modelData.link)
                }
              }
            }

            Text {
              visible: root.todayEvents.length === 0 && root.fetchError === ""
              width: parent.width
              text: "No events today"
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // ================================================================
          //  TAB 1: THIS WEEK
          // ================================================================
          Column {
            visible: root.activeTab === 1
            width: parent.width
            spacing: Style.space(10)

            Repeater {
              model: root.eventGroups

              Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(4)

                Text {
                  text: Model.formatDayHeader(modelData.date).toUpperCase()
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: true
                }

                Repeater {
                  model: modelData.events

                  Rectangle {
                    required property var modelData
                    width: parent.parent.width
                    height: wEvRow.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: wEvMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                    opacity: Model.isEventPast(modelData) ? 0.4 : 1.0

                    Row {
                      id: wEvRow
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)

                      Rectangle {
                        width: Style.space(6)
                        height: Style.space(6)
                        radius: Style.space(3)
                        color: Model.eventCalendarColor(modelData, root.calendars)
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        width: Style.space(52)
                        anchors.verticalCenter: parent.verticalCenter
                        text: Model.isAllDayEvent(modelData) ? "All day" : (modelData.startTime || "")
                        color: wEvMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                      }

                      Text {
                        width: parent.width - Style.space(52) - Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title || "(No title)"
                        color: wEvMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                      }
                    }

                    MouseArea {
                      id: wEvMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: modelData.link !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: root.openEvent(modelData.link)
                    }
                  }
                }
              }
            }

            Text {
              visible: root.weekEvents.length === 0 && root.fetchError === ""
              width: parent.width
              text: "No events this week"
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // ================================================================
          //  TAB 2: MONTH CALENDAR + EVENTS LIST
          // ================================================================
          Column {
            visible: root.activeTab === 2
            width: parent.width
            spacing: Style.space(6)

            // Month navigation
            Item {
              width: parent.width
              height: monthNav.height

              Item {
                id: monthNav
                anchors.horizontalCenter: parent.horizontalCenter
                width: monthGrid.width
                height: monthLabel.implicitHeight + Style.space(6)

                Text {
                  id: monthLabel
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(130)
                  horizontalAlignment: Text.AlignHCenter
                  text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy").toUpperCase()
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1
                }

                PanelActionButton {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅁"
                  tooltipText: "Previous month"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(-1)
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅂"
                  tooltipText: "Next month"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(1)
                }
              }
            }

            // Month grid
            Column {
              id: monthGrid
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(2)

              // Weekday header
              Row {
                spacing: root.cellSpacing
                Item { width: root.weekColumnWidth; height: Style.space(14) }
                Item { width: Style.space(8); height: Style.space(14) }

                Repeater {
                  model: root.weekdays
                  Text {
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(14)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Model.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              // Full week rows
              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item { width: Style.space(8); height: root.cellHeight }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      required property var modelData
                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      color: dayMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      property int evCount: root.eventsOnDay(modelData.key)

                      Text {
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.inMonth
                          ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }

                      Rectangle {
                        visible: evCount > 0 && modelData.inMonth
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(2)
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(Style.space(16), Style.space(4) + evCount * Style.space(3))
                        height: Style.space(4)
                        radius: Style.space(2)
                        color: Color.accent
                        opacity: 0.7
                      }

                      MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: evCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                          if (evCount > 0) root.setTab(0)
                        }
                      }
                    }
                  }
                }
              }
            }

            // ---- Month events list ----
            Column {
              width: parent.width
              spacing: Style.space(4)

              Rectangle {
                width: parent.width
                height: Style.spacing.hairline
                color: root.contentForeground
                opacity: 0.12
              }

              property var monthEvents: root.monthEventsForView()
              property var monthGroups: Model.groupEventsByDay(monthEvents)
              property int totalPages: Math.ceil(monthEvents.length / root.monthEventsPerPage)
              property int pageStart: root.monthEventsPage * root.monthEventsPerPage
              property var pageEvents: monthEvents.slice(pageStart, pageStart + root.monthEventsPerPage)

              property var visibleGroups: {
                var groups = []
                var shown = 0
                for (var i = 0; i < monthGroups.length; i++) {
                  var g = monthGroups[i]
                  var evs = []
                  for (var j = 0; j < g.events.length; j++) {
                    if (shown >= pageStart && shown < pageStart + root.monthEventsPerPage)
                      evs.push(g.events[j])
                    shown++
                  }
                  if (evs.length > 0) groups.push({ date: g.date, events: evs })
                }
                return groups
              }

              Text {
                text: parent.monthEvents.length + " EVENTS"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              Repeater {
                model: parent.visibleGroups

                Column {
                  required property var modelData
                  width: parent.parent.parent.width
                  spacing: Style.space(4)

                  Text {
                    text: Model.formatDayHeader(modelData.date).toUpperCase()
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  Repeater {
                    model: modelData.events

                    Rectangle {
                      required property var modelData
                      width: parent.parent.parent.parent.width
                      height: mevRow.implicitHeight + Style.space(8)
                      radius: Style.cornerRadius
                      color: mevMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                      opacity: Model.isEventPast(modelData) ? 0.4 : 1.0

                      Row {
                        id: mevRow
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(10)
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(8)

                        Rectangle {
                          width: Style.space(6)
                          height: Style.space(6)
                          radius: Style.space(3)
                          color: Model.eventCalendarColor(modelData, root.calendars)
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          width: Style.space(52)
                          anchors.verticalCenter: parent.verticalCenter
                          text: Model.isAllDayEvent(modelData) ? "All day" : (modelData.startTime || "")
                          color: mevMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.body
                        }

                        Text {
                          width: parent.parent.parent.parent.width - Style.space(52) - Style.space(10)
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.title || "(No title)"
                          color: mevMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.body
                          elide: Text.ElideRight
                        }
                      }

                      MouseArea {
                        id: mevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: modelData.link !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.openEvent(modelData.link)
                      }
                    }
                  }
                }
              }

              // Pagination
              Row {
                visible: parent.totalPages > 1
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(6)

                Rectangle {
                  visible: root.monthEventsPage > 0
                  width: prevLabel.implicitWidth + Style.space(16)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: prevMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                  border.width: 1
                  border.color: Qt.darker(root.contentForeground, 1.4)

                  Text {
                    id: prevLabel
                    anchors.centerIn: parent
                    text: "← Prev"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.monthEventsPage = Math.max(0, root.monthEventsPage - 1)
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: (root.monthEventsPage + 1) + " / " + parent.parent.totalPages
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  visible: root.monthEventsPage < parent.parent.totalPages - 1
                  width: nextLabel.implicitWidth + Style.space(16)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: nextMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                  border.width: 1
                  border.color: Qt.darker(root.contentForeground, 1.4)

                  Text {
                    id: nextLabel
                    anchors.centerIn: parent
                    text: "Next →"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.monthEventsPage = Math.min(parent.parent.parent.totalPages - 1, root.monthEventsPage + 1)
                  }
                }
              }

              Text {
                visible: parent.monthEvents.length === 0
                width: parent.width
                text: "No events this month"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

          // ================================================================
          //  TAB 3: CALENDARS
          // ================================================================
          Column {
            visible: root.activeTab === 3
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: "SELECT CALENDARS TO DISPLAY"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Repeater {
              model: root.calendars

              Rectangle {
                required property var modelData
                width: parent.width
                height: Style.space(32)
                radius: Style.cornerRadius
                color: calMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

                property bool isEnabled: Model.calendarIsEnabled(modelData.id, root.enabledCals)

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  Rectangle {
                    width: Style.space(10)
                    height: Style.space(10)
                    radius: Style.space(5)
                    color: modelData.color || "#4285f4"
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Rectangle {
                    width: Style.space(14)
                    height: Style.space(14)
                    radius: Style.space(3)
                    border.width: 1
                    border.color: Qt.darker(root.contentForeground, 1.4)
                    color: parent.parent.parent.isEnabled ? Color.accent : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      visible: parent.parent.parent.isEnabled
                      text: "✓"
                      color: "white"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    text: modelData.name
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(10) - Style.space(14) - Style.space(20) - Style.space(6) * 4
                    elide: Text.ElideRight
                  }

                  Rectangle {
                    width: Style.space(20)
                    height: Style.space(20)
                    radius: Style.space(10)
                    color: delMouse.containsMouse ? Qt.darker(root.contentForeground, 1.4) : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      text: "×"
                      color: delMouse.containsMouse ? root.contentForeground : Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    MouseArea {
                      id: delMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      preventStealing: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (modelData.id.indexOf("ical-") === 0) {
                          var entry = { id: root.moduleName }
                          for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
                          var urls = []
                          try { urls = JSON.parse(entry.icalUrl || "[]") } catch(e) { urls = entry.icalUrl ? [entry.icalUrl] : [] }
                          if (!Array.isArray(urls)) urls = [urls]
                          var idx = parseInt(modelData.id.substring(5))
                          if (idx >= 0 && idx < urls.length) urls.splice(idx, 1)
                          entry.icalUrl = JSON.stringify(urls)
                          root.settings = entry
                          if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
                          if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
                            root.bar.shell.updateEntryInline(root.moduleName, entry)
                          root.authStatus = "iCal feed removed"
                          Qt.callLater(root.refresh)
                        } else {
                          var entry2 = { id: root.moduleName }
                          for (var k2 in root.settings) if (k2 !== "id") entry2[k2] = root.settings[k2]
                          entry2.accessToken = ""
                          entry2.refreshToken = ""
                          entry2.tokenExpiry = ""
                          root.settings = entry2
                          if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry2
                          if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
                            root.bar.shell.updateEntryInline(root.moduleName, entry2)
                          root.calendars = []
                          root.authStatus = "Google account disconnected"
                          Qt.callLater(root.refresh)
                        }
                      }
                    }
                  }
                }

                MouseArea {
                  id: calMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var cals = root.enabledCals ? root.enabledCals.slice() : []
                    var idx = cals.indexOf(modelData.id)
                    if (idx >= 0) cals.splice(idx, 1)
                    else cals.push(modelData.id)
                    persistCalendars(cals)
                  }
                }
              }
            }

            Text {
              visible: root.calendars.length === 0
              width: parent.width
              text: root.useIcal ? "iCal feed configured" : "Loading calendars..."
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // ================================================================
          //  TAB 4: SETUP
          // ================================================================
          Column {
            visible: root.activeTab === 4
            width: parent.width
            spacing: Style.space(10)

            // ---- Mode indicator ----
            Rectangle {
              width: parent.width
              height: modeRow.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              border.width: 1
              border.color: Qt.darker(root.contentForeground, 1.4)
              color: "transparent"

              Row {
                id: modeRow
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Rectangle {
                  width: Style.space(12)
                  height: Style.space(12)
                  radius: Style.space(6)
                  color: root.useOAuth ? "#4caf50" : (root.useIcal ? "#2196f3" : "#9e9e9e")
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: root.useOAuth ? "Google Calendar (read/write)" : (root.useIcal ? "iCal feed (read-only)" : "Not configured")
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // ---- Bar display options ----
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "BAR DISPLAY"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              // Show next event toggle
              Rectangle {
                width: parent.width
                height: toggleRow1.implicitHeight + Style.space(10)
                radius: Style.cornerRadius
                color: toggleMouse1.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

                Row {
                  id: toggleRow1
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Rectangle {
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: Style.space(3)
                    border.width: 1
                    border.color: Qt.darker(root.contentForeground, 1.4)
                    color: root.showNextEvent ? Color.accent : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      visible: root.showNextEvent
                      text: "✓"
                      color: "white"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    text: "Show next event in bar"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: toggleMouse1
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var entry = { id: root.moduleName }
                    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
                    entry.showNextEvent = !root.showNextEvent
                    root.settings = entry
                    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
                    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
                      root.bar.shell.updateEntryInline(root.moduleName, entry)
                  }
                }
              }

              // Icon only toggle
              Rectangle {
                width: parent.width
                height: toggleRow2.implicitHeight + Style.space(10)
                radius: Style.cornerRadius
                color: toggleMouse2.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

                Row {
                  id: toggleRow2
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Rectangle {
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: Style.space(3)
                    border.width: 1
                    border.color: Qt.darker(root.contentForeground, 1.4)
                    color: root.iconOnly ? Color.accent : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      visible: root.iconOnly
                      text: "✓"
                      color: "white"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    text: "Show only calendar icon (no event text)"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: toggleMouse2
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var entry = { id: root.moduleName }
                    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
                    entry.iconOnly = !root.iconOnly
                    root.settings = entry
                    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
                    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
                      root.bar.shell.updateEntryInline(root.moduleName, entry)
                  }
                }
              }

              // Show today's date toggle
              Rectangle {
                width: parent.width
                height: toggleRow3.implicitHeight + Style.space(10)
                radius: Style.cornerRadius
                color: toggleMouse3.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

                Row {
                  id: toggleRow3
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Rectangle {
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: Style.space(3)
                    border.width: 1
                    border.color: Qt.darker(root.contentForeground, 1.4)
                    color: root.showDate ? Color.accent : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      visible: root.showDate
                      text: "✓"
                      color: "white"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    text: "Show today's date in bar"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: toggleMouse3
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var entry = { id: root.moduleName }
                    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
                    entry.showDate = !root.showDate
                    root.settings = entry
                    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
                    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
                      root.bar.shell.updateEntryInline(root.moduleName, entry)
                  }
                }
              }

              // Tooltip mode selector
              Column {
                width: parent.width
                spacing: Style.space(4)

                Text {
                  text: "TOOLTIP ON HOVER"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: true
                }

                Repeater {
                  model: [
                    { key: "upcoming", label: "Upcoming events (next 5)" },
                    { key: "date", label: "Full date (e.g. Tuesday, August 25)" },
                    { key: "none", label: "Nothing" }
                  ]

                  Rectangle {
                    required property var modelData
                    width: parent.width
                    height: Style.space(32)
                    radius: Style.cornerRadius
                    color: tipMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

                    Row {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(10)

                      Rectangle {
                        width: Style.space(14)
                        height: Style.space(14)
                        radius: Style.space(7)
                        border.width: 1
                        border.color: Qt.darker(root.contentForeground, 1.4)
                        color: root.tooltipMode === modelData.key ? Color.accent : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                          visible: root.tooltipMode === modelData.key
                          anchors.centerIn: parent
                          width: Style.space(6)
                          height: Style.space(6)
                          radius: Style.space(3)
                          color: "white"
                        }
                      }

                      Text {
                        text: modelData.label
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    MouseArea {
                      id: tipMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      preventStealing: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        var entry = { id: root.moduleName }
                        for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
                        entry.tooltipMode = modelData.key
                        root.settings = entry
                        if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
                        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
                          root.bar.shell.updateEntryInline(root.moduleName, entry)
                      }
                    }
                  }
                }
              }
            }
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "Ical feed"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              Text {
                width: parent.width
                text: "Paste your calendar's iCal URL to add a feed. You can add multiple calendars."
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }

              Rectangle {
                width: parent.width
                height: Style.space(32)
                radius: Style.cornerRadius
                border.width: 1
                border.color: Qt.darker(root.contentForeground, 1.4)
                color: "transparent"

                TextInput {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  clip: true
                  verticalAlignment: Text.AlignVCenter
                  text: root.icalInput
                  onTextChanged: root.icalInput = text
                }
              }

              Row {
                spacing: Style.space(6)

                Rectangle {
                  width: icalAddLabel.implicitWidth + Style.space(30)
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: icalAddMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Color.accent

                  Text {
                    id: icalAddLabel
                    anchors.centerIn: parent
                    text: "Add"
                    color: "white"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: icalAddMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      var url = root.icalInput.trim()
                      if (url === "") return
                      var entry = { id: root.moduleName }
                      for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
                      var urls = []
                      try { urls = JSON.parse(entry.icalUrl || "[]") } catch(e) { urls = entry.icalUrl ? [entry.icalUrl] : [] }
                      if (!Array.isArray(urls)) urls = [urls]
                      if (urls.indexOf(url) < 0) urls.push(url)
                      entry.icalUrl = JSON.stringify(urls)
                      root.settings = entry
                      if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
                      if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
                        root.bar.shell.updateEntryInline(root.moduleName, entry)
                      root.icalInput = ""
                      root.authStatus = "iCal feed added"
                      Qt.callLater(root.refresh)
                    }
                  }
                }

                Rectangle {
                  visible: root.icalUrls.length > 0
                  width: icalClearLabel2.implicitWidth + Style.space(30)
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.width: 1
                  border.color: Qt.darker(root.contentForeground, 1.4)

                  Text {
                    id: icalClearLabel2
                    anchors.centerIn: parent
                    text: "Clear all"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.icalInput = ""
                      var entry = { id: root.moduleName }
                      for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
                      entry.icalUrl = "[]"
                      root.settings = entry
                      if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
                      if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
                        root.bar.shell.updateEntryInline(root.moduleName, entry)
                      root.calendars = []
                      root.authStatus = "All iCal feeds cleared"
                      Qt.callLater(root.refresh)
                    }
                  }
                }
              }

              Text {
                visible: root.icalUrls.length > 0
                width: parent.width
                text: root.icalUrls.length + " feed(s) configured"
                color: "#4caf50"
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // Hairline
            Rectangle {
              width: parent.width
              height: Style.spacing.hairline
              color: root.contentForeground
              opacity: 0.12
            }

            // ---- Advanced Settings (OAuth) ----
            Column {
              width: parent.width
              spacing: Style.space(6)

              Rectangle {
                width: advLabel.implicitWidth + Style.space(20)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: advMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                border.width: 1
                border.color: Qt.darker(root.contentForeground, 1.4)

                Row {
                  id: advLabel
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Text {
                    text: root.showAdvanced ? "󰅁" : "󰅂"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    text: "Advanced Settings — Google Calendar (read/write)"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }
                }

                MouseArea {
                  id: advMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showAdvanced = !root.showAdvanced
                }
              }

              // OAuth content (expandable)
              Column {
                visible: root.showAdvanced
                width: parent.width
                spacing: Style.space(10)

                Text {
                  width: parent.width
                  text: "To add events directly from this widget, connect a Google account. You need your own Google OAuth credentials."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }

                // Status message
                Text {
                  visible: root.authStatus !== ""
                  width: parent.width
                  text: root.authStatus
                  color: OAuth.isAuthenticated(root.settings) ? "#4caf50" : Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                }

                // Connect button (when not authenticated)
                Rectangle {
                  visible: !OAuth.isAuthenticated(root.settings) && !root.authenticating && root.authCodeInput === ""
                  width: connectLabel.implicitWidth + Style.space(30)
                  height: Style.space(36)
                  radius: Style.cornerRadius
                  color: connectMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Color.accent

                  Text {
                    id: connectLabel
                    anchors.centerIn: parent
                    text: "Connect to Google"
                    color: "white"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  MouseArea {
                    id: connectMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startAuth()
                  }
                }

                // Auth code input
                Column {
                  visible: root.authenticating || root.authCodeInput !== ""
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    width: parent.width
                    text: "Paste the URL from the browser after authorizing:"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.Wrap
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(32)
                    radius: Style.cornerRadius
                    border.width: 1
                    border.color: Qt.darker(root.contentForeground, 1.4)
                    color: "transparent"

                    TextInput {
                      anchors.fill: parent
                      anchors.margins: Style.space(8)
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      clip: true
                      verticalAlignment: Text.AlignVCenter
                      text: root.authCodeInput
                      onTextChanged: root.authCodeInput = text
                    }
                  }

                  Rectangle {
                    width: submitLabel.implicitWidth + Style.space(30)
                    height: Style.space(32)
                    radius: Style.cornerRadius
                    color: submitMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : Color.accent

                    Text {
                      id: submitLabel
                      anchors.centerIn: parent
                      text: root.authenticating ? "Connecting..." : "Connect"
                      color: "white"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                    }

                    MouseArea {
                      id: submitMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.submitAuthCode()
                      enabled: !root.authenticating
                    }
                  }
                }

                // Disconnect (when authenticated)
                Rectangle {
                  visible: OAuth.isAuthenticated(root.settings)
                  width: discLabel.implicitWidth + Style.space(30)
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.width: 1
                  border.color: Qt.darker(root.contentForeground, 1.4)

                  Text {
                    id: discLabel
                    anchors.centerIn: parent
                    text: "Disconnect"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root._updateSettings({
                        access_token: undefined,
                        refresh_token: undefined,
                        expires_at: undefined
                      })
                      root.allEvents = []
                      root.todayEvents = []
                      root.weekEvents = []
                      root.eventGroups = []
                      root.calendars = []
                      root.authStatus = "Disconnected"
                    }
                  }
                }

                // Setup script info
                Column {
                  visible: !OAuth.isAuthenticated(root.settings)
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    width: parent.width
                    text: "Or run the setup script in a terminal:"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }

                  Rectangle {
                    width: parent.width
                    height: setupScriptLabel.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: Qt.darker(root.contentForeground, 0.9)

                    Text {
                      id: setupScriptLabel
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: "omarchy plugin run io.github.fullo.gcal setup"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.Wrap
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  function persistCalendars(cals) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry.enabledCalendars = JSON.stringify(cals)
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    Qt.callLater(root.refresh)
  }
}
