# Task Manager

A practical task manager for Windows and Android that works both offline and online.

It is designed for people who want more control over where their task data is stored. You can use the app entirely offline, without an account or cloud connection, or enable synchronization when you need the same tasks on multiple devices or want to share folders and tasks with another person.

Unlike many task apps, cloud access is optional rather than required. The local database remains the primary source of truth, so the app stays usable without internet access and does not depend on a remote service for basic task management.

> **Status:** Active development. Core task management, reminders, backup, synchronization, and shared tasks are implemented. Some interfaces and data structures may still change.

## Why Use It

- **Offline when privacy matters** — keep tasks only on the device and use the app without an account.
- **Online when convenience matters** — synchronize tasks between Windows and Android.
- **Shared work when coordination matters** — share folders, tasks, and checklists with another registered user.
- **Local-first reliability** — tasks remain available when the network is slow, unavailable, or the sync service is temporarily unreachable.
- **Desktop and mobile support** — use the same task system on a Windows computer and an Android phone.

## Main Features

- Tasks, notes, due dates, priorities, tags, folders, subtasks, recurrence, snooze, and pinning
- Checklists and reusable checklist templates
- Calendar and smart-filter views
- Local reminders on Windows and Android
- Local database backup and restore
- Optional Supabase authentication and synchronization
- Shared folders, tasks, and checklists
- Windows tray integration and compact task view

## Screenshots

<img width="990" height="566" alt="image" src="https://github.com/user-attachments/assets/c30f1663-5106-4a27-9ce9-17b08fbbb765" />
<img width="740" height="530" alt="image" src="https://github.com/user-attachments/assets/b2aa355a-6410-4745-90f8-73f226c1fdae" />
<img width="292" height="448" alt="image" src="https://github.com/user-attachments/assets/f3a0cbac-1b87-4076-b099-e5892f184c95" />

## Offline or Online

### Offline mode

Use offline mode when you want the simplest setup or do not want task data stored in the cloud.

- No account required
- No internet connection required
- Data stays in the local SQLite database
- Backup and restore are handled locally

### Online mode

Use online mode when you need synchronization or collaboration.

- Keep tasks synchronized between Windows and Android
- Work with the same folders and checklists on multiple devices
- Share selected folders, tasks, and checklists with another user
- Continue working locally when temporarily offline and synchronize later

Online mode uses a self-configured Supabase backend. Cloud synchronization is optional and can be omitted completely.

## Supported Platforms

| Platform | Status |
| --- | --- |
| Windows 10/11 x64 | Supported |
| Android | Supported |
| Web | Planned |
| macOS, Linux, iOS | Not currently supported |

## Getting Started

### Requirements

- Flutter SDK with Dart `>=3.3.0 <4.0.0`
- Visual Studio with **Desktop development with C++** for Windows builds
- Android Studio or Android SDK for Android builds

Check the development environment:

```powershell
flutter doctor -v
```

Install dependencies and generate the database code:

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Run Offline

```powershell
flutter run -d windows
```

Choose offline mode on the authentication screen. Supabase configuration is not required.

### Enable Online Sync

```powershell
Copy-Item supabase.env.example supabase.env
```

Add your Supabase project URL and publishable key, then apply:

- `supabase/schema.sql`
- migrations from `supabase/migrations/`

Start the Windows application with:

```powershell
.\run.bat
```

See [Supabase setup](docs/SUPABASE_SETUP.md) for the complete procedure.

> Never add a Supabase `service_role` key, database password, signing key, or other private credential to the repository or a client build.

## Development Checks

```powershell
flutter analyze
flutter test
```

Build release packages with:

```powershell
.\export.bat
```

Or build one platform:

```powershell
.\export.bat -Platform windows
.\export.bat -Platform android
```

See [installation and export](docs/INSTALL_AND_EXPORT.md) for packaging, signing, and installation details.

## Technology

- Flutter and Dart
- Riverpod
- Drift and SQLite
- Supabase Auth, Postgres, Realtime, and Row Level Security
- Flutter local notifications
- Secure OS credential storage

## Data and Security

- SQLite is the local source of truth.
- Cloud synchronization is optional.
- Local databases, backups, environment files, signing keys, and release builds are excluded from Git.
- Cloud data access is protected with Supabase Row Level Security.
- Pending changes are stored locally and retried when synchronization becomes available.

Before running a public Supabase instance, review all policies and migrations in `supabase/`.

## Known Limitations

- No web client yet
- Attachments are not uploaded to Supabase Storage
- Search currently uses local substring matching instead of SQLite FTS
- Android and Windows application identifiers will be replaced in the future update

## License

Copyright (С) 2026 

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
