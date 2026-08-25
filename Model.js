.pragma Library

var MS_PER_DAY = 86400000
var CALENDAR_API = "https://www.googleapis.com/calendar/v3"
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Google Calendar API ----

function fetchAgenda(token, enabledCals, callback) {
    if (!token) { callback([]); return }
    var now = new Date()
    var end = new Date(now.getTime() + 30 * MS_PER_DAY)
    var url = CALENDAR_API + "/calendars/primary/events"
        + "?timeMin=" + now.toISOString()
        + "&timeMax=" + end.toISOString()
        + "&singleEvents=true"
        + "&orderBy=startTime"
        + "&maxResults=50"
    _apiGet(token, url, function(data) {
        if (!data || !data.items) { callback([]); return }
        var events = data.items.map(function(ev) { return _parseEvent(ev) })
        if (enabledCals && enabledCals.length > 0) {
            events = events.filter(function(e) {
                return enabledCals.indexOf(e.calendar) >= 0
            })
        }
        callback(events)
    })
}

function fetchCalendars(token, callback) {
    if (!token) { callback([]); return }
    _apiGet(token, CALENDAR_API + "/users/me/calendarList", function(data) {
        if (!data || !data.items) { callback([]); return }
        callback(data.items.map(function(cal) {
            return { id: cal.id, name: cal.summary, access: cal.accessRole }
        }))
    })
}

function _apiGet(token, url, callback) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) callback(JSON.parse(xhr.responseText))
            else if (xhr.status === 401) callback(null) // token expired
            else callback(null)
        }
    }
    xhr.send()
}

function _parseEvent(ev) {
    var start, end, dateStr, startTime = "", endTime = ""
    if (ev.start.date) {
        // All-day event
        dateStr = ev.start.date
        startTime = ""
        endTime = ""
    } else {
        var sd = new Date(ev.start.dateTime)
        var ed = new Date(ev.end.dateTime)
        dateStr = _dateKeyFromDate(sd)
        startTime = _formatTime(sd)
        endTime = _formatTime(ed)
    }
    var parsed = _parseEventDatetime(dateStr, startTime)
    return {
        date: dateStr,
        startTime: startTime,
        endTime: endTime,
        startParsed: parsed,
        link: ev.htmlLink || "",
        title: ev.summary || "",
        location: ev.location || "",
        description: ev.description || "",
        calendar: ev.organizer ? (ev.organizer.email || "") : "",
        allDay: !!ev.start.date
    }
}

function _formatTime(d) {
    var h = d.getHours(), m = d.getMinutes()
    var ampm = h >= 12 ? "PM" : "AM"
    var h12 = h % 12 || 12
    return h12 + ":" + (m < 10 ? "0" : "") + m + " " + ampm
}

function _dateKeyFromDate(date) {
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function _parseEventDatetime(dateStr, timeStr) {
    if (!dateStr || !timeStr) return null
    var cleanTime = timeStr.replace(/\s/g, "")
    var match = cleanTime.match(/^(\d{1,2}):(\d{2})(AM|PM)?$/i)
    if (!match) return null
    var hours = parseInt(match[1], 10)
    var minutes = parseInt(match[2], 10)
    var ampm = match[3] ? match[3].toUpperCase() : null
    if (ampm === "PM" && hours < 12) hours += 12
    if (ampm === "AM" && hours === 12) hours = 0
    var dateParts = dateStr.split("-")
    if (dateParts.length !== 3) return null
    return new Date(parseInt(dateParts[0], 10), parseInt(dateParts[1], 10) - 1, parseInt(dateParts[2], 10), hours, minutes)
}

// ---- Event helpers (kept from v1) ----

function isAllDayEvent(event) {
    return event.allDay || !event.startTime || event.startTime.trim() === ""
}

function minutesUntil(event) {
    if (!event.startParsed) return null
    return Math.round((event.startParsed.getTime() - Date.now()) / 60000)
}

function formatTimeUntil(minutes) {
    if (minutes === null) return ""
    if (minutes < 0) return "now"
    if (minutes < 60) return minutes + "m"
    var hours = Math.floor(minutes / 60)
    var mins = minutes % 60
    if (hours < 24) return hours + "h" + (mins > 0 ? " " + mins + "m" : "")
    var days = Math.floor(hours / 24)
    return days + "d"
}

function formatEventTime(event) {
    if (isAllDayEvent(event)) return "All day"
    var s = event.startTime || "", e = event.endTime || ""
    return (s && e) ? s + " – " + e : s
}

// ---- Today / this week events ----

function eventsForToday(events) {
    var today = dateKeyFromDate(new Date())
    return events.filter(function(e) { return e.date === today })
}

function eventsForThisWeek(events) {
    var now = new Date()
    var start = startOfWeek(now)
    var end = new Date(start.getTime() + 7 * MS_PER_DAY)
    return events.filter(function(e) {
        if (!e.startParsed) return false
        return e.startParsed.getTime() >= start.getTime() && e.startParsed.getTime() < end.getTime()
    })
}

// ---- Month grid ----

function dateKey(year, month, day) {
    return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

function startOfWeek(date) {
    var d = new Date(date)
    var day = d.getDay()
    d.setDate(d.getDate() - day)
    d.setHours(0, 0, 0, 0)
    return d
}

function isoWeek(year, month, day) {
    var d = new Date(Date.UTC(year, month, day))
    var wd = d.getUTCDay() || 7
    d.setUTCDate(d.getUTCDate() + 4 - wd)
    var y0 = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
    return Math.ceil(((d.getTime() - y0.getTime()) / MS_PER_DAY + 1) / 7)
}

function monthGrid(year, month, weekStart, todayKey) {
    var start = (weekStart || 1)
    var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
    var cursor = new Date(year, month, 1 - leading)
    var today = String(todayKey || "")
    var weeks = []
    for (var w = 0; w < 6; w++) {
        var days = []
        var thursday = null
        for (var d = 0; d < 7; d++) {
            var cy = cursor.getFullYear(), cm = cursor.getMonth(), cd = cursor.getDate()
            var wd = cursor.getDay(), key = dateKey(cy, cm, cd)
            if (wd === 4) thursday = { year: cy, month: cm, day: cd }
            days.push({ key: key, year: cy, month: cm, day: cd, weekday: wd, inMonth: cm === month && cy === year, weekend: wd === 0 || wd === 6, today: key === today })
            cursor.setDate(cursor.getDate() + 1)
        }
        var anchor = thursday || days[0]
        weeks.push({ week: isoWeek(anchor.year, anchor.month, anchor.day), days: days })
    }
    return weeks
}

function stepMonth(year, month, delta) {
    var t = new Date(year, Number(month) + Number(delta), 1)
    return { year: t.getFullYear(), month: t.getMonth() }
}

function weekdayOrder(weekStart) {
    var s = weekStart || 1
    var out = []
    for (var i = 0; i < 7; i++) out.push((s + i) % 7)
    return out
}

function weekdayLabel(weekday) {
    return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
}

// ---- Grouping & display ----

function groupEventsByDay(events) {
    var groups = {}, order = []
    for (var i = 0; i < events.length; i++) {
        var key = events[i].date || "unknown"
        if (!groups[key]) { groups[key] = []; order.push(key) }
        groups[key].push(events[i])
    }
    var result = []
    for (var j = 0; j < order.length; j++)
        result.push({ date: order[j], events: groups[order[j]] })
    return result
}

function formatDayHeader(dateStr) {
    if (!dateStr) return ""
    var parts = dateStr.split("-")
    if (parts.length !== 3) return dateStr
    var date = new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10))
    var today = new Date(), tomorrow = new Date()
    tomorrow.setDate(tomorrow.getDate() + 1)
    if (date.toDateString() === today.toDateString()) return "Today"
    if (date.toDateString() === tomorrow.toDateString()) return "Tomorrow"
    var dn = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    var mn = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    return dn[date.getDay()] + ", " + mn[date.getMonth()] + " " + date.getDate()
}

// ---- Bar label ----

function formatBarLabel(events) {
    if (!events || events.length === 0) return ""
    var now = new Date()
    var next = null
    for (var i = 0; i < events.length; i++) {
        if (events[i].startParsed && events[i].startParsed.getTime() > now.getTime()) { next = events[i]; break }
    }
    if (!next) next = events[events.length - 1]
    if (!next) return ""
    var mins = minutesUntil(next)
    var timeStr = formatTimeUntil(mins)
    var title = next.title || ""
    if (title.length > 20) title = title.substring(0, 18) + "…"
    if (timeStr === "now") return "󰃭 " + title
    if (mins !== null && mins >= 0) return "󰃭 " + timeStr + " " + title
    return "󰃭 " + title
}

function formatBarTooltip(events) {
    if (!events || events.length === 0) return "No upcoming events"
    var lines = ["Upcoming (" + events.length + "):"]
    for (var i = 0; i < Math.min(events.length, 5); i++) {
        var e = events[i], t = isAllDayEvent(e) ? "All day" : (e.startTime || "")
        lines.push("  " + t + "  " + (e.title || ""))
    }
    if (events.length > 5) lines.push("  … and " + (events.length - 5) + " more")
    return lines.join("\n")
}

// ---- Calendar filter helpers ----

function settingsEnabledCals(settingValue) {
    if (!settingValue || settingValue === "") return null
    try { var a = JSON.parse(settingValue); return Array.isArray(a) ? a : null } catch(e) { return null }
}

function calendarIsEnabled(calName, enabledCals) {
    if (!enabledCals) return true
    if (enabledCals.length === 0) return true
    for (var i = 0; i < enabledCals.length; i++) {
        if (enabledCals[i] === calName) return true
    }
    return false
}
