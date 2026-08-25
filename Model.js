var MS_PER_DAY = 86400000
var CALENDAR_API = "https://www.googleapis.com/calendar/v3"

// ---- iCal parsing ----

function fetchIcal(url, callback) {
    if (!url || url === "") { callback([]); return }
    var xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    xhr.timeout = 30000
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) callback(parseIcal(xhr.responseText))
            else callback([])
        }
    }
    xhr.onerror = function() { callback([]) }
    xhr.ontimeout = function() { callback([]) }
    xhr.send()
}

function parseIcal(raw) {
    var lines = unfoldLines(String(raw || ""))
    var events = []
    var inEvent = false
    var ev = {}
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "")
        if (line === "BEGIN:VEVENT") { inEvent = true; ev = {} }
        else if (line === "END:VEVENT") { inEvent = false; events.push(ev) }
        else if (inEvent) {
            var colon = line.indexOf(":")
            if (colon < 0) continue
            var key = line.substring(0, colon)
            var val = line.substring(colon + 1)
            // Strip params from key (e.g. "DTSTART;VALUE=DATE" -> "DTSTART")
            var semi = key.indexOf(";")
            var bareKey = semi >= 0 ? key.substring(0, semi) : key
            if (bareKey === "DTSTART") ev.dtstart = parseIcalDatetime(val, key)
            else if (bareKey === "DTEND") ev.dtend = parseIcalDatetime(val, key)
            else if (bareKey === "SUMMARY") ev.title = unescapeIcal(val)
            else if (bareKey === "LOCATION") ev.location = unescapeIcal(val)
            else if (bareKey === "DESCRIPTION") ev.description = unescapeIcal(val)
            else if (bareKey === "URL") ev.link = val
        }
    }
    return events.filter(function(e) { return e.dtstart }).map(function(e) {
        var allDay = !e.dtstart.time
        var dateStr = e.dtstart.date
        var startTime = allDay ? "" : e.dtstart.time
        var endTime = e.dtend ? (allDay ? "" : e.dtend.time) : ""
        return {
            date: dateStr,
            startTime: startTime,
            endTime: endTime,
            startParsed: e.dtstart.parsed,
            link: e.link || "",
            title: e.title || "",
            location: e.location || "",
            description: e.description || "",
            calendar: "",
            allDay: allDay
        }
    }).sort(function(a, b) {
        if (!a.startParsed || !b.startParsed) return 0
        return a.startParsed.getTime() - b.startParsed.getTime()
    })
}

function unfoldLines(raw) {
    // iCal continuation lines start with space/tab
    return raw.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
        .split("\n")
        .reduce(function(acc, line) {
            if (line.match(/^[ \t]/) && acc.length > 0) acc[acc.length - 1] += line.substring(1)
            else acc.push(line)
            return acc
        }, [])
}

function parseIcalDatetime(val, fullKey) {
    // Format: 20260825T143000Z or 20260825 (all-day)
    var clean = val.replace(/Z$/, "").replace(/T/g, " ").replace(/:/g, " ").replace(/\s+/g, " ").trim()
    var parts = clean.split(" ")
    var isAllDay = fullKey && fullKey.indexOf("VALUE=DATE") >= 0
    if (parts.length < 2) {
        // Try all-day: 20260825
        if (val.length === 8) {
            var y = parseInt(val.substring(0, 4))
            var m = parseInt(val.substring(4, 6)) - 1
            var d = parseInt(val.substring(6, 8))
            return { date: dateKey(y, m, d), time: "", parsed: new Date(y, m, d) }
        }
        return null
    }
    // Date part: 20260827
    var dateStr = parts[0]
    if (dateStr.length !== 8) return null
    var y = parseInt(dateStr.substring(0, 4))
    var m = parseInt(dateStr.substring(4, 6)) - 1
    var d = parseInt(dateStr.substring(6, 8))
    // Time part: 070000 or 07 00 00
    if (parts.length === 2) {
        // "20260827 070000" — time as single token
        var timeToken = parts[1]
        var h = parseInt(timeToken.substring(0, 2))
        var min = parseInt(timeToken.substring(2, 4))
        var sec = parseInt(timeToken.substring(4, 6)) || 0
        var ampm = h >= 12 ? "PM" : "AM"
        var h12 = h % 12 || 12
        var timeStr = h12 + ":" + pad2(min) + " " + ampm
        return { date: dateKey(y, m, d), time: timeStr, parsed: new Date(y, m, d, h, min, sec) }
    }
    // "20260827 07 00 00" or "20260827 07 00" — time split into tokens
    var h = parseInt(parts[1])
    var min = parseInt(parts[2])
    var sec = parseInt(parts[3]) || 0
    var ampm = h >= 12 ? "PM" : "AM"
    var h12 = h % 12 || 12
    var timeStr = h12 + ":" + pad2(min) + " " + ampm
    return { date: dateKey(y, m, d), time: timeStr, parsed: new Date(y, m, d, h, min, sec) }
}

function unescapeIcal(val) {
    return val.replace(/\\n/g, "\n").replace(/\\,/g, ",").replace(/\\\\/g, "\\")
}

// ---- Google Calendar API (OAuth mode) ----

function fetchGoogleAgenda(token, enabledCals, callback) {
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
        var events = data.items.map(function(ev) { return _parseGoogleEvent(ev) })
        if (enabledCals && enabledCals.length > 0) {
            events = events.filter(function(e) {
                return enabledCals.indexOf(e.calendar) >= 0
            })
        }
        callback(events)
    })
}

function fetchGoogleCalendars(token, callback) {
    if (!token) { callback([]); return }
    _apiGet(token, CALENDAR_API + "/users/me/calendarList", function(data) {
        if (!data || !data.items) { callback([]); return }
        callback(data.items.map(function(cal) {
            return { id: cal.id, name: cal.summary, access: cal.accessRole, color: cal.backgroundColor || "#4285f4" }
        }))
    })
}

function createGoogleEvent(token, event, callback) {
    if (!token || !callback) { if (callback) callback(false); return }
    var body = {
        summary: event.title || "",
        location: event.location || "",
        description: event.description || ""
    }
    if (event.allDay) {
        body.start = { date: event.date }
        body.end = { date: event.date }
    } else {
        body.start = { dateTime: event.startParsed ? event.startParsed.toISOString() : "" }
        body.end = { dateTime: event.endParsed ? event.endParsed.toISOString() : "" }
    }
    var xhr = new XMLHttpRequest()
    xhr.open("POST", CALENDAR_API + "/calendars/primary/events")
    xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) callback(xhr.status === 200 || xhr.status === 201)
    }
    xhr.send(JSON.stringify(body))
}

function _apiGet(token, url, callback) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) callback(JSON.parse(xhr.responseText))
            else callback(null)
        }
    }
    xhr.send()
}

function _parseGoogleEvent(ev) {
    var start, end, dateStr, startTime = "", endTime = ""
    if (ev.start.date) {
        dateStr = ev.start.date
    } else {
        var sd = new Date(ev.start.dateTime)
        var ed = new Date(ev.end.dateTime)
        dateStr = _dateKeyFromDate(sd)
        startTime = _formatTime(sd)
        endTime = _formatTime(ed)
    }
    return {
        date: dateStr,
        startTime: startTime,
        endTime: endTime,
        startParsed: ev.start.dateTime ? new Date(ev.start.dateTime) : new Date(dateStr),
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
    return h12 + ":" + pad2(m) + " " + ampm
}

function _dateKeyFromDate(date) {
    return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

// ---- Event helpers ----

function isAllDayEvent(event) {
    return event.allDay || !event.startTime || event.startTime.trim() === ""
}

function isEventPast(event) {
    if (!event.startParsed) return false
    return event.startParsed.getTime() < Date.now()
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

// ---- Today / this week ----

function eventsForToday(events) {
    var today = dateKeyFromDate(new Date())
    return events.filter(function(e) { return e.date === today })
}

function firstEventForDay(events, dayKey) {
    for (var i = 0; i < events.length; i++) {
        if (events[i].date === dayKey) return events[i]
    }
    return null
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

function dateKeyFromDate(date) {
    return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
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

function eventCalendarColor(event) {
    // For iCal: blue. For OAuth: would need calendar colors from API
    return "#4fa8de"
}

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

function calendarIsEnabled(calId, enabledCals) {
    if (!enabledCals) return true
    if (enabledCals.length === 0) return true
    for (var i = 0; i < enabledCals.length; i++) {
        if (enabledCals[i] === calId) return true
    }
    return false
}
