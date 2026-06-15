# xcfb

[![CI](https://github.com/rryam/xcfb/actions/workflows/ci.yml/badge.svg)](https://github.com/rryam/xcfb/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.0+-fa7343?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14.0+-000000?style=flat&logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Agent-first CLI for Apple Feedback Assistant workflows on macOS.

xcfb prepares, files, and verifies Feedback Assistant reports. It can inspect the local Feedback Assistant store, generate structured report payloads, drive Apple's native app through Accessibility, and use an experimental authenticated web workflow for server-backed drafts and confirmed submission.

xcfb is distributed only as an executable. Its Swift package manifest is the build definition for the CLI and exports no library product.

The CLI is optimized for agents: create a machine-readable JSON payload, review the generated Markdown report, fill the native app or a server-backed draft, and submit only after explicit confirmation.

```sh
xcfb prepare \
  --title "Xcode canvas stops updating after file rename" \
  --description "Steps, expected result, actual result." \
  --snapshot ./snapshot.png \
  --bundle-id com.apple.dt.Xcode \
  --platform macOS \
  --kind bug

xcfb submit --payload feedback-submission.json --select-popups --dry-run
xcfb submit --payload feedback-submission.json --select-popups
```

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode command line tools
- Feedback Assistant installed and signed in, for native commands
- Accessibility permission for Terminal, if you use native form filling
- A password-based Apple Account, if you use experimental `xcfb web` commands

## Installation

Build from source:

```sh
git clone https://github.com/rryam/xcfb.git
cd xcfb
swift build -c release
.build/release/xcfb --help
.build/release/xcfb version
```

Install the built executable somewhere on your `PATH`:

```sh
install -m 755 .build/release/xcfb ~/.local/bin/xcfb
```

## What It Does

xcfb gives you a small command-line workflow around the native Feedback Assistant app:

- read-only inspection of the local Feedback Assistant store
- topic and area inference from title, description, bundle identifier, and curated Feedback Assistant area mappings
- JSON and Markdown report preparation
- native Feedback Assistant route launching
- AX-driven title, description, bundle ID, platform/technology/type popup selection, and submit handoff
- background local attachment staging into Feedback Assistant draft folders
- fail-closed behavior when native controls require focus, keyboard, or pointer ownership

The experimental web command family additionally provides:

- headless Apple Account SRP login implemented in Swift
- trusted-device and trusted-phone two-factor authentication
- prompt-free Feedback Assistant session storage with owner-only permissions
- live session validation against Apple's Appleseed service
- read-only inbox, form catalog, and form schema JSON
- server-backed submitted feedback details
- server-backed draft creation from a form ID
- explicit confirmed draft submission with server receipt verification

## First Commands

Inspect the local store:

```sh
xcfb store summary
xcfb store list --limit 20
xcfb store uploads
xcfb categories
```

Check routing and categorization:

```sh
xcfb routes
xcfb open new --print-only
xcfb categorize \
  --title "Xcode preview fails to refresh" \
  --description "The canvas stops updating after renaming a SwiftUI file." \
  --bundle-id com.apple.dt.Xcode
```

xcfb uses curated mappings for common Feedback Assistant destinations, including macOS app/system areas, Developer Tools areas, Developer Technologies frameworks, and top-level platform forms such as iOS & iPadOS, watchOS, tvOS, visionOS, HomePod, AirPods, Enterprise & Education, MFi, and DMA Interoperability.

Prepare a report:

```sh
xcfb prepare \
  --title "Xcode preview fails to refresh" \
  --description "Steps to reproduce, expected result, and actual result." \
  --snapshot ./snapshot.png \
  --bundle-id com.apple.dt.Xcode \
  --platform macOS \
  --kind bug
```

`xcfb prepare` writes two files:

- `feedback-submission.json` - the machine-readable payload used by `xcfb open-native`, `xcfb fill`, and `xcfb submit`
- `feedback-submission.md` - the human-readable report for agent review, logs, notes, or evidence attachments

`--snapshot` can point to any local evidence file, including a screenshot, Markdown note, log, sample project archive, or sysdiagnose pointer. `--platform` accepts `iOS`, `iPadOS`, `Mac Catalyst`, `macOS`, `tvOS`, `visionOS`, `watchOS`, or `Web & Services`; it is inferred from the title and description when omitted.

Open and fill the native app:

```sh
xcfb open-native --payload feedback-submission.json
xcfb fill --payload feedback-submission.json --select-popups
```

Submit through the native app with explicit confirmation:

```sh
xcfb submit --payload feedback-submission.json --select-popups --dry-run
xcfb submit --payload feedback-submission.json --select-popups --confirm
```

Without `--confirm`, `xcfb submit` fills the fields it can safely set, hides Feedback Assistant again, stages the snapshot, and stops before Submit. When `--select-popups` is present, Feedback Assistant is briefly activated so Accessibility can select native platform, technology, and feedback-type menu items.

With `--confirm`, xcfb asks the signed-in native app to press Submit through Accessibility, then performs best-effort local store verification. This check can show local store changes and matching recent items, but it is not a server-side receipt from Apple.

Feedback Assistant may add required native-only fields based on the selected topic, such as popups, Xcode version, device details, logs, or sysdiagnose attachments. Review those fields in the app before using `--confirm`.

## Commands

```sh
xcfb store summary [--db PATH]
xcfb store list [--limit N] [--db PATH]
xcfb store uploads [--limit N] [--db PATH]
xcfb categories [--db PATH]
xcfb categorize --title TEXT [--description TEXT] [--bundle-id ID]
xcfb prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]
xcfb routes
xcfb open ROUTE [--id ID] [--print-only]
xcfb open-native [--payload PATH]
xcfb fill [--payload PATH] [--select-popups]
xcfb submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]
xcfb web auth login --apple-id EMAIL [--two-factor-code-command COMMAND]
xcfb web auth status
xcfb web auth logout
xcfb web inbox list [--locale LOCALE] [--team-id ID] [--compact]
xcfb web feedback view --id ID [--locale LOCALE] [--compact]
xcfb web feedback status --id ID [--locale LOCALE] [--compact]
xcfb web forms list [--locale LOCALE] [--team-id ID] [--compact]
xcfb web forms view --id ID [--locale LOCALE] [--team-id ID] [--compact]
xcfb web forms options --id ID [--tat TAT] [--locale LOCALE] [--team-id ID] [--compact]
xcfb web drafts create --form-id ID [--locale LOCALE] [--team-id ID] [--compact]
xcfb web drafts view --id ID [--locale LOCALE] [--compact]
xcfb web drafts update --id ID [--payload PATH] [field options] [--answer TAT=VALUE]... [--locale LOCALE] [--compact]
xcfb web drafts attach --id ID [--file PATH]... [--payload PATH] [--locale LOCALE] [--compact]
xcfb web drafts validate --id ID [--locale LOCALE] [--compact]
xcfb web drafts submit --id ID --confirm [--locale LOCALE] [--compact]
xcfb version
```

Agent-oriented help:

```sh
xcfb help payload
xcfb help submit
xcfb help fill
xcfb help store
xcfb help web
```

## Experimental Web Access

`xcfb web` connects directly to `https://appleseed.apple.com/sp/`. It does not use the public App Store Connect API, ASC's private Iris API, Chrome, WebKit, or another CLI.

Authenticate:

```sh
xcfb web auth login --apple-id "developer@example.com"
xcfb web auth status
```

The login command performs Apple's password-based SRP exchange directly in Swift. By default it reads the password and any verification code from secure terminal prompts. It supports trusted-device and trusted-phone two-factor authentication, stores only the resulting Feedback Assistant cookies and a one-way account hash, and never prints credential or cookie values.

Web sessions default to `~/.xcfb/web/session.json`. xcfb creates the directory with mode `0700`, atomically replaces the session file with mode `0600`, and rejects session files with group or other access. This avoids recurring macOS Keychain approval prompts when a locally built unsigned CLI changes identity after every rebuild. The file contains bearer session cookies and must not be synced, shared, or committed.

For a stable signed binary, opt into macOS Keychain storage:

```sh
XCFB_WEB_SESSION_BACKEND=keychain xcfb web auth login --apple-id "developer@example.com"
```

Set `XCFB_WEB_SESSION_DIR` to override the file cache directory.

For non-interactive agents, set `XCFB_WEB_APPLE_ID` and `XCFB_WEB_PASSWORD`, and optionally provide `--two-factor-code-command COMMAND` or `XCFB_WEB_2FA_CODE_COMMAND`. The command must print only the current verification code to stdout. Environment-provided passwords are convenient for automation but are less private than the secure prompt.

This path does not open WebKit, Chrome, or the ASC binary. Passkey-only accounts and Apple Account prompts that require browser interaction are not supported by the headless experiment.

Inspect server data:

```sh
xcfb web inbox list
xcfb web feedback view --id FEEDBACK_ID
xcfb web feedback status --id FEEDBACK_ID
xcfb web forms list
xcfb web forms view --id FORM_ID
xcfb web forms options --id FORM_ID --tat :area
xcfb web drafts create --form-id FORM_ID
xcfb web drafts view --id DRAFT_ID
xcfb web drafts update \
  --id DRAFT_ID \
  --title "Foundation Models framework: add first-class video input support" \
  --platform macOS \
  --technology "Foundation Models Framework" \
  --kind suggestion \
  --description "$REPORT_BODY" \
  --foundation-models-mode feedback
xcfb web drafts attach \
  --id DRAFT_ID \
  --file ./evidence.md
xcfb web drafts validate --id DRAFT_ID
xcfb web drafts submit --id DRAFT_ID --confirm
```

Raw inspection commands emit Apple's JSON response directly. `feedback view` reads the same server-backed detail envelope Apple's web client uses for a submitted report, while `feedback status` returns Apple's current status rows. `forms options` normalizes each question into its TAT, widget, requirement state, condition rules, and label/value choices. Draft updates fetch the current draft and form schema, preserve untouched answers, resolve labels such as `Foundation Models Framework` to Apple's submitted value, enforce Apple's 255-character text-field and 4096-character text-area limits, and then save the complete answer set.

Use `--payload feedback-submission.json` to import the common fields generated by `xcfb prepare`. Named options override payload values. Repeat `--answer TAT=VALUE` for conditional or topic-specific questions; repeated values for the same TAT are submitted as a checkbox array.

`drafts attach` accepts repeated `--file` options or reads the snapshot path from `--payload`. Each file is created as an Apple file promise, uploaded to the returned presigned object URL without Apple Account headers, marked uploaded, and verified by reading the draft back. Presigned URLs are never printed or persisted.

`drafts validate` evaluates the current form's visible conditional questions and required answers before submission. Required File Zone questions are satisfied only by an uploaded file promise, so an uploaded attachment and a staged local path are not conflated.

`drafts submit` requires `--confirm` with no alias. It reruns the schema-driven preflight, saves the complete answer set using Apple's special Required File Zone representation, sends the final draft mutation, and verifies the returned `FB` identifier against Apple's submitted-feedback detail endpoint. The command fails closed before authentication or network access when `--confirm` is absent, and it refuses survey drafts because Apple submits those through a different workflow.

Clear the cached session:

```sh
xcfb web auth logout
```

This surface is unofficial and may break without notice. Draft creation, draft inspection, form option discovery, answer updates, attachment upload, submission payload construction, and receipt reads follow Apple's current web client contracts.

## Automation Model

xcfb uses an Objective-C Accessibility engine for native form automation. It writes supported text fields through passive AX value updates. With `--select-popups`, it briefly activates Feedback Assistant and uses native AX menu actions to select platform, technology, and feedback type. It does not synthesize mouse movement, pointer clicks, or keyboard input.

Local snapshots are staged into Feedback Assistant's local draft folder after the native draft exists. This avoids driving the visible Add Attachment menu and keeps the user's active app undisturbed where macOS allows it.

Some Feedback Assistant controls are native-only by design. Diagnostics prompts, device selections, and log-gathering flows may still require review inside Apple's app. When a requested control or menu item is unavailable, xcfb fails closed instead of pretending the form was completed.

For the automation model, see [docs/AX_AUTOMATION.md](docs/AX_AUTOMATION.md).

## Safety Boundaries

xcfb keeps the stable native workflow separate from the experimental web workflow:

- `xcfb submit --confirm` presses the native Submit button through Accessibility.
- Local store verification is local evidence only. It can show drafts, recent items, and upload-task changes, but it is not an Apple server receipt.
- Private FeedbackCore and feedbackd APIs are not used by the shipping CLI.
- Experimental `xcfb web` commands use password-based Apple SRP authentication and keep only the resulting session. File storage is owner-only by default; Keychain storage is opt-in.
- `xcfb web drafts submit --confirm` uses Apple's undocumented Appleseed service and verifies the returned feedback ID through a server read.
- xcfb does not bypass entitlements, forge Apple credentials, patch platform security, or redistribute Apple private headers.

## Maturity

xcfb is pre-1.0. The stable surface is report preparation, local store inspection, native route launch, text-field fill, native popup selection, local attachment staging, explicit native submit handoff, and best-effort local verification. The `xcfb web` command family is experimental.

## Non-Goals

- No entitlement bypass.
- No forged Apple credentials.
- No SIP or platform security workarounds.
- No redistribution of Apple private headers or copied framework code.

## Build

```sh
swift build
swift test
swift build -c release
make check
```

## Documentation

- [docs/COMMANDS.md](docs/COMMANDS.md) - generated command reference
- [docs/AX_AUTOMATION.md](docs/AX_AUTOMATION.md) - native Accessibility automation notes
- [CONTRIBUTING.md](CONTRIBUTING.md) - development workflow
- [SUPPORT.md](SUPPORT.md) - support checklist
- [SECURITY.md](SECURITY.md) - security reporting and project boundary

## License

MIT

---

<p align="center">
  <sub>xcfb is an independent, unofficial tool and is not affiliated with, endorsed by, or sponsored by Apple Inc. Apple, macOS, Xcode, and Feedback Assistant are trademarks of Apple Inc.</sub>
</p>
