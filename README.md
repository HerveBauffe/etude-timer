Application Vibe-coded.

# Étude Timer (Flutter edition, v2.0)

Desktop app for Windows/Linux that tracks study time per course, with two timer methods
(Pomodoro, Flow Zone), statistics (heatmap, graphs, weekly/monthly summary, exam-cram periods) and
data sync over WebDAV (Nextcloud or any other server).

## Features

- **Organization**: folders (year, semester…) → course unit (UE) → course. Create / rename / delete at
  every level, move a UE to another folder, archive finished UEs (history is kept; "Archives" section).
- **Pomodoro**: adjustable work block (default 25 min), short/long breaks (long break after N blocks).
  Each phase is started manually. When the target is reached you get a sound + desktop notification +
  the window comes to the front, **but the timer keeps running** (overtime) so your real study time is
  recorded. **Pause/Resume** (not counted as a break) and **Skip** (jump straight to the next phase).
  Breaks are never recorded. **End study session** saves the running block silently and *then* offers
  an optional note — the only moment a note is requested.
- **Flow Zone**: free stopwatch. On stop you get a review screen (optional note) and an earned break
  (adjustable % of the time worked) that you can start or skip.
- **Notes**: a "Resume" banner shows the latest note of the selected course; a "Note" button adds one
  anytime without a timer.
- **Manual time**: "Temps" button to add duration + date after the fact; ✎ on any history entry to fix
  its duration/date.
- **Statistics**: today/week/month cards, yearly heatmap, minutes-per-day line chart (30/90/365 days),
  monthly total with ISO-week breakdown, per-course filter. Only work time counts.
- **Blocus (exam-cram periods)**: named date ranges; for the filtered course, one independent total per
  blocus next to the total over the whole period. Several blocus can coexist; deleting one never deletes
  study time.
- **WebDAV sync**: at startup, at a regular interval, on close (5 s max) and on demand. See below.
- **Data location**: default per-OS folder, **portable mode**, or any folder you choose.
- **Single instance**: launching the app twice brings the existing window to the front.

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) **3.32 or newer** (stable), with desktop support.
- Linux build dependencies: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`
- Windows: Visual Studio 2022 with the "Desktop development with C++" workload.

## First run

The platform folders (`windows/`, `linux/`) are generated, not versioned:

```bash
./scripts/bootstrap.sh          # Linux/macOS shell   (Windows: scripts\bootstrap.ps1)
flutter run -d linux            # or: flutter run -d windows
```

`bootstrap` runs `flutter create --platforms=windows,linux --project-name etude_timer .`, removes the
sample widget test and runs `flutter pub get`.

## Build

```bash
./scripts/build_linux.sh                                              # Linux  → dist/*.tar.gz
powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1    # Windows → dist\*.zip (portable)
```

Both scripts print the real size of the build folder and of the archive. An optional Windows installer
script for [Inno Setup](https://jrsoftware.org/isinfo.php) is in `installer/etude_timer.iss`.

**About size.** Flutter always ships its engine (a native library plus the ICU data file), so the
unpacked folder will not be as tiny as a native app. The app code itself is small: only two plugins
(`window_manager`, `file_selector`), no `flutter_localizations` (French strings are a hand-written
delegate), no charting library (chart and heatmap are drawn with `CustomPaint`). Measure the result
with the build scripts; the zipped/compressed size is what matters for distribution.

## Data

| What | Windows | Linux |
|---|---|---|
| Default folder | `%APPDATA%\etude-timer` | `~/.config/etude-timer` (or `$XDG_CONFIG_HOME`) |
| Portable | `EtudeTimerData\` next to the `.exe` | `EtudeTimerData/` next to the executable |

- `data.json` — your data (same location and format family as the Electron version; it is simply picked up).
- `location.json` — pointer to a custom data folder (Settings → Data location).
- `device.json` — settings specific to this computer (WebDAV credentials, last sync). **Never uploaded.**

Portable mode: create a folder named `EtudeTimerData` next to the executable (the Windows build script
already does it for the portable zip). Remove it to switch back to the default location.

### Migrating from the Electron version

Run the new app: it reads the existing `data.json`. WebDAV URL/user/path are imported once into
`device.json`. If the old password was encrypted by Electron it cannot be read here — re-enter it in
Settings.

## WebDAV sync

Settings → WebDAV. For Nextcloud the URL looks like
`https://cloud.example.com/remote.php/dav/files/<user>`; the file defaults to `/EtudeTimer/data.json`
(folders are created if missing). Use a Nextcloud **app password** (Settings → Security).

- Merge is per item: the most recent modification wins, nothing is lost when two machines edit
  different things. **Deletions propagate** (tombstones, kept one year). An item edited after it was
  deleted elsewhere is kept.
- The upload uses `If-Match`/`If-None-Match` (ETag): if the remote file changed meanwhile, the app
  re-reads and re-merges instead of overwriting. An unreadable remote file is never overwritten.
- Nothing is uploaded when there is nothing new.
- TLS certificate validation is never disabled: a server with a self-signed certificate must be
  trusted by the OS.
- The password is stored **in clear text** in `device.json` (permissions 600 on Linux). Use an app
  password.

## Alerts

- Sound: Linux plays the freedesktop "complete" sound if `canberra-gtk-play` or `paplay` exists,
  otherwise the system beep; Windows uses the system beep.
- Desktop notification: Linux via `notify-send` (if installed). **No Windows toast**: on Windows the
  window is brought to the front and a message is shown in the app.

## Tests

The business logic (`lib/core/`) has no Flutter dependency and is covered by tests:

```bash
flutter test
```

They cover the store (including reading a 1.x `data.json`), sync/merge (two simulated machines with an
in-memory server), the WebDAV client (against a local fake server), Pomodoro/Flow state machines (fake
clock), statistics, blocus and the single-instance lock.

## Project layout

```
lib/core/       pure Dart: models, data_store, paths, device_config, webdav_client, sync,
                pomodoro, flow, stats, formatting, single_instance
lib/platform/   window management (window_manager), sound/notifications
lib/ui/         Material 3 app: theme, controller, screens (timer, stats, settings), widgets
test/           unit tests for lib/core
scripts/        bootstrap + build scripts      installer/   Inno Setup script
```