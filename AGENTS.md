# GrotTrack

A macOS menu bar app that tracks activity, plus a Chrome extension that feeds it browser tab data.

`arch.txt` holds the architecture and design principles and is authoritative. An architecture change
is not finished until `arch.txt` is in sync with it.

## Build

- `GrotTrack.xcodeproj` is generated from `project.yml` and gitignored. `just setup` installs the
  toolchain and generates it; re-run `just xcodeproj` after any `project.yml` change. Never edit or
  commit the project file.
- Deployment target is macOS 26.0 with `SWIFT_STRICT_CONCURRENCY: complete`. `AppState` and
  `AppCoordinator` are `@MainActor`; anything crossing an isolation boundary is `Sendable`.
- `GrotTrackNativeHost` is a second target: a CLI embedded inside `GrotTrack.app/Contents/MacOS/`
  and launched by Chrome over native messaging. It shares `NativeMessageHost.swift` and
  `SharedConstants.swift` with the app target, so a change to either is a change to both.
- The extension in `grot-track-extension/` is built with WXT. Its native messaging host config JSON
  must be installed at
  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.grottrack.tabtracker.json`,
  and the host name in it must stay `com.grottrack.tabtracker`.
- Run `just` with stdin from `/dev/null`. No recipe is confirmation-gated today; if one is added,
  ask before running it rather than passing a non-interactive approval flag.

## Task tracking

The board is the only source of truth for what is left. The **Wave operating model** document
(`backlog doc list --plain` to find it) carries this project's own rules: the single-Mac exclusive
resource, the generated `.xcodeproj`, the four recurring defect classes, lane conventions and
run-end.

The rules below deliberately sit outside the tool-managed marker block, so an upstream instruction
block update cannot silently drop them.

- **Never pass `--notes` or `--plan` bare.** They replace the whole section at exit 0 and another
  session's writes vanish with no warning. Use `--append-notes` and `--append-plan`. A global
  `PreToolUse` hook denies the unsafe forms.
- **Hand-editing task, draft, doc, decision or milestone markdown is silently destructive.** Section
  boundaries are HTML comment markers; break one and the section is dropped at exit 0 - the data
  stays in the file but is invisible to the CLI until the next write destroys it for real. There is
  no repair command: `backlog doctor` only repairs duplicate task ids. `backlog/config.yml` is the
  one exception and has to be hand-edited, because its list-valued keys are not in
  `backlog config set`'s key enum.
- **Finalize in one call**, so an interruption cannot leave finished work looking unfinished:
  `backlog task edit GRT-0001 --check-ac 1 --check-ac 2 -s Done`.

`backlog/` is committed to git, so it carries no real identifiers: no email addresses, handles,
usernames, account ids, device or host names, paths under a real home directory, Chrome Web Store or
Apple Developer identifiers, or values copied out of a real SwiftData store or screenshot. This app
watches the user's own screen and browser, so the temptation is constant. Write the shape, not the
instance: "the browser's active tab", `<app>/<window title>`. Aggregate counts, timings and
structural findings are fine. Sweep before committing:

```bash
grep -rniE "rob-knight\.com|@gmail|@grafana|\bknightion\b" backlog/ && echo "PII FOUND"
```

<!-- BACKLOG.MD GUIDELINES START -->
<!-- backlog.md-instructions-version: 1.50.1 -->
<CRITICAL_INSTRUCTION>

## Backlog.md Workflow

This project uses Backlog.md for task and project management.

**For every user request in this project, run `backlog instructions overview` before answering or taking action.**

Use the overview to decide whether to search, read, create, or update Backlog tasks.

Before task lifecycle actions, read the matching detailed guide:
- `backlog instructions task-creation` before creating or splitting tasks
- `backlog instructions task-execution` before planning, changing status or assignee, adding a plan or implementation notes, or implementing task work
- `backlog instructions task-finalization` before checking acceptance criteria, writing final summaries, or moving tasks to terminal statuses

Use `backlog <command> --help` before running unfamiliar commands. Help shows options, fields, and examples.

Do not edit Backlog task, draft, document, decision, or milestone markdown files directly. Use the `backlog` CLI so metadata, relationships, and history stay consistent.

</CRITICAL_INSTRUCTION>
<!-- BACKLOG.MD GUIDELINES END -->
