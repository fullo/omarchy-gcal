# io.github.fullo.gcal — Google Calendar for Omarchy

A bar widget plugin for [Omarchy](https://omarchy.org/) that displays upcoming Google Calendar events directly in the status bar, with a full-featured panel for browsing your schedule.

Uses the Google Calendar API with OAuth 2.0 — no external dependencies required.

## Features

- **Bar widget** — shows the next upcoming event with time-until countdown
- **Today tab** — all events for the current day with times, locations, and links
- **Week tab** — events grouped by day for the current week
- **Month tab** — full calendar grid with event dot indicators and week numbers
- **Calendars tab** — select which Google calendars to display
- **Setup tab** — in-panel OAuth configuration
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

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a project (or use an existing one)
3. Enable the **Google Calendar API**
4. Create **OAuth 2.0 credentials** (Desktop application)
5. Set the redirect URI to: `http://localhost:1`
6. Open the plugin panel (click the calendar icon in the bar)
7. Go to the **Setup** tab
8. Enter your Client ID and Client Secret, click **Save Credentials**
9. Click **Authenticate with Google** and authorize the app
10. After authorization, you'll be redirected to `localhost` which won't load — copy the full URL from the address bar and paste it into the code field

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

- **enabledCalendars** — JSON array of calendar IDs to show (empty = all calendars)

## License

MIT
