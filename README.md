Application Vibe-coded.

# Étude Timer (Flutter edition, v2.2)

App for Windows/Linux **and Android** (phone and tablet) that tracks study time per course, with two timer methods
(Pomodoro, Flow Zone), statistics (heatmap, graphs, weekly/monthly summary, exam-cram periods) and
data sync over WebDAV (Nextcloud or any other server).

This is a rewrite of the Electron version (1.x) in **Flutter**, with the goal of a much smaller
package and a simpler interface (Material You, black-and-white dark theme by default). All features
of 1.1.0 are kept; existing `data.json` files are read as-is.

## Features

- **Organization**: folders (year, semester…) → course unit (UE) → course. Create / rename / delete at
  every level, move a UE to another folder, archive finished UEs (history is kept; "Archives" section).
- **Quadrimesters**: each course belongs to **one** quadrimester (Q1 or Q2); a UE can span both (its
  span is derived from its courses). A **Q1 / Q2 / Q1+Q2 toggle** in the side bar, just above the sync
  button, filters the courses shown in every screen (timer, courses, planning, statistics). The choice
  is remembered per computer (`device.json`).
- **Courses tab**: manage and reorganize folders, UEs and courses (create, rename, change a course's
  quadrimester, move a course to another UE, archive, delete, "Study this course").
- **Timer tab**: the courses of the selected quadrimester are always in a side panel, expanded by
  default and collapsible.
- **Planning**: calendar with **month** and **week** views. A **revision** has a title, a course and an
  optional estimated work duration; an **exam** has a title, a course, a date and a time. Revisions
  can be ticked as done; the next exam is shown with a countdown.
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
  monthly total with ISO-week breakdown, per-course filter, and **study time per course** (all time /
  this month / this week). Only work time counts. Everything follows the quadrimester filter.
- **Blocus (exam-cram periods)**: named date ranges; for the filtered course, one independent total per
  blocus next to the total over the whole period. Several blocus can coexist; deleting one never deletes
  study time.
- **WebDAV sync**: at startup, at a regular interval, on close (5 s max) and on demand. See below.
- **Data location**: default per-OS folder, **portable mode**, or any folder you choose.
- **Single instance**: launching the app twice brings the existing window to the front.

## Android (phone and tablet)

The same code base builds for Android. The layout adapts to the screen:

| Width | Layout |
|---|---|
| < 600 dp (phone) | top bar with the **Q1 / Q2 / Q1+Q2** toggle and the sync button, **bottom navigation bar**; the course list of the timer tab opens in a bottom sheet ("Choisir un cours"); compact month calendar (dots + list of the selected day) |
| 600–900 dp (tablet portrait) | side navigation bar like on desktop; course list in a bottom sheet |
| ≥ 900 dp (tablet landscape) | same as desktop: side bar + collapsible course panel next to the timer |

- Data lives in the app's private storage; there is no folder picker, **the way to move data between
  devices is the WebDAV sync** (same server + same file path as on the computer: the `data.json` format is
  identical). Android's automatic backup covers the study data but **excludes `device.json`** (WebDAV
  password), see `tool/patch_android.dart`.
- The system **Back** button returns to the timer tab; during a running session it never closes the app.
- End-of-phase alert on Android: **vibration** + in-app message. Timers are based on the clock, so the
  elapsed time is correct when you come back to the app.
- **Limitation (first Android release):** there is no background service yet. If the screen is off or the
  app is in the background, Android may pause the app: no sound/notification at the end of a phase until
  you come back, and if the system kills the app, the running (unsaved) block is lost. Keep the app open
  during a session for now (a foreground service + notification is the planned next step).
- WebDAV over plain `http://` is blocked by Android by default (use `https://`).

Build (needs the Android SDK and JDK 17, see `flutter doctor`):

```bash
./scripts/bootstrap.sh            # once: generates android/ and patches it (INTERNET permission, backup rules)
flutter run                       # on a connected device/emulator
./scripts/build_android.sh        # → dist/app-arm64-v8a-release.apk (+ other ABIs); --aab for a bundle
```

Without a signing key (`android/key.properties`), release builds are signed with the debug key: fine to
install on your own devices, not for publishing.

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) **3.35 or newer** (stable; developed and statically checked against 3.47), with desktop support.
- Linux build dependencies: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`
- Windows: Visual Studio 2022 with the "Desktop development with C++" workload.
- Android: Android SDK + JDK 17 (Android Studio installs both).

## First run

The platform folders (`windows/`, `linux/`) are generated, not versioned:

```bash
./scripts/bootstrap.sh          # Linux/macOS shell   (Windows: scripts\bootstrap.ps1)
flutter run -d linux            # or: flutter run -d windows
```

`bootstrap` runs `flutter create --platforms=windows,linux,android --project-name etude_timer .`, removes the
sample widget test, runs `flutter pub get` and `dart tool/patch_android.dart` (INTERNET permission is
missing from the generated release manifest, WebDAV would silently fail without it).

## Build

```bash
./scripts/build_linux.sh                                              # Linux  → dist/*.tar.gz
powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1    # Windows → dist\*.zip (portable)
```

Both scripts print the real size of the build folder and of the archive. An optional Windows installer
script for [Inno Setup](https://jrsoftware.org/isinfo.php) is in `installer/etude_timer.iss`.

**About size.** Flutter always ships its engine (a native library plus the ICU data file), so the
unpacked folder will not be as tiny as a native app. The app code itself is small: only three plugins
(`window_manager`, `file_selector`, `path_provider`), no `flutter_localizations` (French strings are a hand-written
delegate), no charting library (chart and heatmap are drawn with `CustomPaint`). Measure the result
with the build scripts; the zipped/compressed size is what matters for distribution.

## Data

| What | Windows | Linux |
|---|---|---|
| Default folder | `%APPDATA%\etude-timer` | `~/.config/etude-timer` (or `$XDG_CONFIG_HOME`) |
| Portable | `EtudeTimerData\` next to the `.exe` | `EtudeTimerData/` next to the executable |

- `data.json` — your data (same location and format family as the Electron version; it is simply picked up).
- `location.json` — pointer to a custom data folder (Settings → Data location).
- `device.json` — settings specific to this computer (WebDAV credentials, last sync, quadrimester filter). **Never uploaded.**

Portable mode: create a folder named `EtudeTimerData` next to the executable (the Windows build script
already does it for the portable zip). Remove it to switch back to the default location.

Data format version is now **3** (`Course.quadri`, new `plans` list). Older files are read as-is: for a
course without quadrimester, it is inferred from the names of its folders/UE ("Q1", "Q2", "2e quadri",
"semestre 2"…), otherwise Q1. **Check the Courses tab after the first launch.** The inference is
deterministic, so two machines converge to the same result. Do not sync an old (Electron) and the new
app on the same remote file.

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
in-memory server, plans included), the WebDAV client (against a local fake server), Pomodoro/Flow state
machines (fake clock), statistics (including per-course totals), blocus, the quadrimester filter and
legacy migration, the planning calendar, the single-instance lock and the Android project patch (117 tests).

## Project layout

```
lib/core/       pure Dart: models, data_store, quadri, catalog, planning, paths, device_config,
                webdav_client, sync, pomodoro, flow, stats, formatting, single_instance
lib/platform/   window management (window_manager), sound/vibration/notifications
lib/ui/         Material 3 app: theme, controller, screens (timer, courses, planning, stats,
                settings), widgets (course sidebar, dialogs, charts)
test/           unit tests for lib/core
scripts/        bootstrap + build scripts      installer/   Inno Setup script
tool/           patch_android.dart (manifest + backup rules for the generated android/ folder)
```

## Known limitations

- No tray icon, no drag-and-drop reordering, no CSV export, no sync conflict UI (automatic merge only).
- Android: no background service/notification yet (see above), no iOS build.
- Desktop has no wallpaper-based dynamic color; Material You is provided through seed palettes
  (black-and-white by default, plus teal, indigo, rose, amber).
- Flow Zone breaks are no longer recorded in the data (they never counted in statistics anyway).
