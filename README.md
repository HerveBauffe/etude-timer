Application Vibe-coded.

# Étude Timer
Desktop app for Windows/Linux that allows study time tracking, with 2 tracking methods (Pomodoro, FlowZone), statistics (Heatmap, graphs, weekly/monthly summary) and data sync using WebDAV (Nextcloud or other)

## Features

- **Organization**: folders (e.g., year, semester) → course unit → class, with the ability to rename,
  delete, and archive completed course units (time history is retained).
- **Pomodoro Timer**: 25-minute work block (adjustable). Once the 25 minutes are up, notifications alerts but **the timer continues to run** to
  track your total time.
  After 4 blocks, a 15-minute long break. Break time is never recorded in the
  statistics. A **End Study Session** button ends everything at any
  time and saves the current work time and allows you to take note of your progress.
- **Flow Zone Timer**: a free-form timer; when paused, the app calculates a well-deserved break
  (an adjustable percentage of the time worked) that you can start immediately.
- **Study Notes**: At the end of your study session (using the “End Study Session” button),
  you can add an optional note (e.g., “page 42, exercise 3”…). The most recent note
  for a course is highlighted as soon as you select it, so you can pick up where you left off more quickly. A
  “+ Note” button also lets you add one at any time, without starting a timer.
- **Manual Time**: A “⏱ Time” button lets you add study time retroactively (duration +
  date), which is useful if you forgot to start or stop the timer. Each entry in
  the recent history can also be edited later using the ✎ icon (duration and date).
- **Statistics**: a heatmap showing contribution patterns, a graph of the number of
  minutes studied per day (30/90/365 days), the total for the current month, and a week-by-week
  breakdown, with a filter by course.
- **WebDAV Synchronization**: Data (structure + history + notes) is stored in
  a single JSON file, synchronized to your WebDAV server (typically Nextcloud) at
  startup, at regular intervals, on shutdown, and on demand. The password is encrypted
  on disk when the system allows it (always on Windows; on Linux if a keyring
  — GNOME Keyring, KWallet, etc. — is available).

## Prerequisites

- [Node.js](https://nodejs.org/) 18 or newer (LTS recommended), with npm.
- On Linux, to compile a `.deb`/`AppImage` package: standard build tools
  (`build-essential` on Debian/Ubuntu) are generally not required, but install them
  if `npm install` fails for a native module.

## Installation and Launch in Development

```bash
npm install
npm start
```

This launches the application directly with Electron, without creating an installer. This is the
fastest way to try it out or make changes to it.

## Creating Installation Packages

```bash
# Windows (.exe installer + portable version)
npm run dist:win

# Linux (.AppImage + .deb)
npm run dist:linux

# Both at once (requires the ability to compile for both platforms,
# which generally works best by running each command on its own OS)
npm run dist
```

The generated files are located in `release/`. **Tip**: `electron-builder` compiles more
easily for Windows when running on Windows and for Linux when running on Linux

A default Electron icon will be used until you add your own to
`build/icon.ico` (Windows) and `build/icon.png` (Linux, 512×512 recommended)—electron-builder
automatically detects them at these locations.

## Configure Nextcloud Synchronization (WebDAV)
1. In Nextcloud: **Settings → Security → Create a new app password**,
   give it a name (e.g., “Etude Timer”) and copy the generated password—do not use your
   main password.
2. Your WebDAV URL is usually:
   `https://YOUR-NEXTCLOUD.exemple.com/remote.php/dav/files/YOUR_USERNAME/`
3. In the app, go to the **Settings → WebDAV Sync** tab:
   - Enable synchronization.
   - Enter the URL, your Nextcloud username, and the app password created in
     step 1.
   - The “Remote Path” field (`/EtudeTimer/data.json` by default) is the file that will be created
     on your Nextcloud to store all your data—the folder is created automatically.
   - Click **Save**, then **Sync Now** to verify that everything
     is working.
4. Repeat this setup (same URL, same username, same app password) on
   your second computer.

### How Synchronization works

With each synchronization, the local and remote folders/UE/courses/sessions
are **merged by identifier**—a record added on one side
is never lost. If the same item is modified on both sides between two syncs, the version of the dataset that was most recently modified
is retained. A sync occurs automatically on startup, every
*N* minutes (configurable), and when the app closes (with a 5-second limit so as not to
block the shutdown).

## Where is the data stored?

In a `data.json` file located in the app’s data folder:

- **Windows**: `%APPDATA%\etude-timer\data.json`
- **Linux**: `~/.config/etude-timer/data.json`

This is the same file that is sent to your WebDAV server. You can back it up
manually at any time by simply copying it.

## Known Limitations / Areas for Improvement

- Icon in the system notification area (tray) to keep the timer visible when the window
  is minimized.
- Reorganize folders/UEs via drag-and-drop.
- A true conflict resolution dialog in case you modify both machines at the same
  time without syncing between them (currently handled by automatic merging; see
  above).
- CSV export of sessions for external analysis.

## Security and Dependency Maintenance

The project is set up to use recent versions of Electron and electron-builder (`npm audit`
returns 0 vulnerabilities at the time of writing). During installation, `npm` may display
`deprecated` warnings for deeply nested packages.
Run `npm outdated` and `npm audit` from time to time to keep Electron up to date (security fixes are frequent).

## Project Structure

```
src/
  main/         Electron main process (window, JSON storage, WebDAV sync, notifications)
  renderer/     interface (vanilla HTML/CSS/JS, no framework or bundler required)
    views/      Timer, Statistics, Settings, sidebar
    lib/        shared state, formatting, hand-drawn SVG graphics, modals
```

No front-end framework or bundler (webpack/vite) is used: the renderer loads
native ES modules directly (`<script type="module">`), which keeps the project easy to read
and modify without an intermediate build step.
