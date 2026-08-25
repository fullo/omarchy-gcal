# fullo.gcal — Google Calendar for Omarchy

A bar widget plugin for [Omarchy](https://omarchy.org/) that displays upcoming Google Calendar events directly in the status bar, with a full-featured panel for browsing your schedule.

## Features

- **Bar widget** — shows the next upcoming event with time-until countdown
- **Today tab** — all events for the current day with times, locations, and links
- **Week tab** — events grouped by day for the current week
- **Month tab** — full calendar grid with event dot indicators and week numbers
- **Calendars tab** — select which Google calendars to display
- **Auto-refresh** — updates every 5 minutes
- **Keyboard navigation** — 1/2/3/4 to switch tabs, `t` for today, `[/]` to step months

## Requirements

- [gcalcli](https://github.com/insanum/gcalcli) — must be installed and authenticated
  ```bash
  # Arch Linux (AUR)
  yay -S gcalcli

  # First-time setup
  gcalcli list
  ```

## Installation

```bash
omarchy plugin add https://github.com/fullo/omarchy-gcal.git --enable
```

Or manually clone into your plugins directory:

```bash
git clone https://github.com/fullo/omarchy-gcal.git ~/.config/omarchy/plugins/fullo.gcal
```

The plugin will appear in the bar after the next shell reload (automatic on file save).

## Configuration

The plugin is configured through the Omarchy shell bar layout in `~/.config/omarchy/shell.json`. Add it to the `center`, `left`, or `right` section:

```json
{
  "id": "fullo.gcal"
}
```

### Settings

- **enabledCalendars** — JSON array of calendar names to show (empty = all calendars)

## License

MIT
