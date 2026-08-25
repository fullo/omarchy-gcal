# io.github.fullo.gcal — iCal Calendar for Omarchy

A bar widget plugin for [Omarchy](https://omarchy.org/) that displays upcoming iCal feed events directly in the status bar, with a full-featured panel for browsing your schedule.

Uses standard iCal/ICS feeds — no external dependencies, no API keys required.

## Features

- **Bar widget** — shows the next upcoming event with time-until countdown
- **Today tab** — all events for the current day with times, locations, and links
- **Week tab** — events grouped by day for the current week
- **Month tab** — full calendar grid with event dot indicators and week numbers
- **Calendars tab** — select which iCal feeds to display
- **Setup tab** — add/remove iCal feed URLs, toggle 24h/12h time format
- **Auto-refresh** — updates every 5 minutes
- **Keyboard navigation** — 1-5 to switch tabs, `t` for today, `[/]` to step months

## Requirements

- [Omarchy](https://omarchy.org/) with Quickshell

## Installation

```bash
omarchy plugin add https://github.com/fullo/omarchy-gcal.git --enable
```

Or manually clone:

```bash
git clone https://github.com/fullo/omarchy-gcal.git ~/.config/omarchy/plugins/io.github.fullo.gcal
```

## Setup

1. Open the plugin panel (click the calendar icon in the bar)
2. Go to the **Setup** tab
3. Paste your iCal/ICS feed URL(s) — supports multiple feeds
4. Click **Add**
5. Use the **Calendars** tab to toggle which feeds are visible

## Removal

```bash
omarchy plugin remove io.github.fullo.gcal
```

## Configuration

The plugin is configured through the Omarchy shell bar layout in `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.fullo.gcal"
}
```

### Settings

- **icalUrl** — JSON array of iCal feed URLs
- **enabledCalendars** — JSON array of calendar IDs to show (empty = all calendars)
- **timeFormat** — "24h" (default) or "12h" for AM/PM display

## License

MIT
