import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

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

  // View state
  property int activeTab: 0
  property int viewYear: new Date().getFullYear()
  property int viewMonth: new Date().getMonth()
  readonly property string todayKey: Model.dateKeyFromDate(new Date())

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

  // Event count on a given day key
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
    if (!agendaProc.running) agendaProc.running = true
    if (!listProc.running) listProc.running = true
  }

  function buildGcalcliArgs() {
    var args = ["gcalcli", "--tsv", "--nocolor", "agenda"]
    var cals = root.enabledCals
    if (cals) {
      for (var i = 0; i < cals.length; i++) args.push("--cal", cals[i])
    }
    return args
  }

  function openEvent(link) {
    if (link && link !== "") Qt.openUrlExternally(link)
  }

  function setTab(idx) { root.activeTab = idx }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function goToToday() {
    var now = new Date()
    root.viewYear = now.getFullYear()
    root.viewMonth = now.getMonth()
  }

  // ---- Process: agenda ----

  Process {
    id: agendaProc
    command: root.buildGcalcliArgs()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        root.allEvents = raw ? Model.parseTsvAgenda(raw) : []
        root.todayEvents = Model.eventsForToday(root.allEvents)
        root.weekEvents = Model.eventsForThisWeek(root.allEvents)
        root.eventGroups = Model.groupEventsByDay(root.weekEvents)
        root.fetchError = root.allEvents.length === 0 ? "No upcoming events" : ""
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.allEvents = []
        root.todayEvents = []
        root.weekEvents = []
        root.eventGroups = []
        root.fetchError = "gcalcli error (is it installed?)"
      }
    }
  }

  // ---- Process: calendar list ----

  Process {
    id: listProc
    command: ["gcalcli", "--nocolor", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.calendars = Model.parseCalendarList(text)
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

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

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
              model: ["Today", "Week", "Month", "Calendars"]

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
              text: Qt.formatDate(new Date(), "EEEE, MMMM d").toUpperCase()
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

                Row {
                  id: evRow
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Column {
                    width: Style.space(68)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      text: Model.isAllDayEvent(modelData) ? "All day" : (modelData.startTime || "")
                      color: evMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      visible: !Model.isAllDayEvent(modelData) && modelData.endTime !== ""
                      text: "to " + (modelData.endTime || "")
                      color: Qt.darker(root.contentForeground, 1.6)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
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
                    width: parent.width - Style.space(68) - Style.space(10) - Style.spacing.hairline - Style.space(10)
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

                    Row {
                      id: wEvRow
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(10)

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
          //  TAB 2: MONTH CALENDAR
          // ================================================================
          Item {
            visible: root.activeTab === 2
            width: parent.width
            height: monthColumn.height

            Column {
              id: monthColumn
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

                // Header row
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

                // Week rows
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

                        // Event dot indicator
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
                          cursorShape: evCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                          onClicked: {
                            if (evCount > 0) {
                              // Switch to today/week view if clicking a day with events
                              root.setTab(0)
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
                height: calRow.implicitHeight + Style.space(10)
                radius: Style.cornerRadius
                color: calMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"

                property bool isEnabled: Model.calendarIsEnabled(modelData.name, root.enabledCals)

                Row {
                  id: calRow
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  // Checkbox
                  Rectangle {
                    width: Style.space(16)
                    height: Style.space(16)
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
                    width: parent.width - Style.space(16) - Style.space(10)
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: modelData.access !== ""
                    text: modelData.access
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: calMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    // Toggle calendar - save to settings
                    var cals = root.enabledCals ? root.enabledCals.slice() : []
                    var idx = cals.indexOf(modelData.name)
                    if (idx >= 0) cals.splice(idx, 1)
                    else cals.push(modelData.name)
                    persistCalendars(cals)
                  }
                }
              }
            }

            Text {
              visible: root.calendars.length === 0
              width: parent.width
              text: "Run gcalcli list to see calendars"
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
              horizontalAlignment: Text.AlignHCenter
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
    // Refresh after filter change
    Qt.callLater(root.refresh)
  }
}
