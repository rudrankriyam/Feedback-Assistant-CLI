# Command Reference

This file is generated from live CLI help output. RelatoKit is optimized for agent-driven Feedback Assistant workflows.

## Agent Flow

1. Research the issue and write supporting evidence to a local file.
2. Run `relato prepare` to create `feedback-submission.json` and `feedback-submission.md`.
3. Inspect both files before touching the native app.
4. Run `relato submit --dry-run --select-popups --payload feedback-submission.json`.
5. Run `relato submit --select-popups --payload feedback-submission.json` to fill safe fields, select known native popups, stage attachments, and stop before Submit.
6. Inspect Feedback Assistant for native-only fields, popups, diagnostics, and staged attachments.
7. Use `--confirm` only after explicit user confirmation.
8. Use `relato store list` and `relato store uploads` as local evidence afterward; they are not Apple server receipts.
9. Use `relato web` only for the isolated experimental read-only web workflow.

## Payload Contract

- `feedback-submission.json` is the machine-readable contract used by `open-native`, `fill`, and `submit`.
- `feedback-submission.md` is the human-readable review artifact for logs, notes, or attachments.
- `--snapshot PATH` can point to any local evidence file, not only an image.
- `--platform PLATFORM` records the native platform popup value; it is inferred from the report when omitted.

## Global Help

```sh
relato: agent-first tooling for Apple Feedback Assistant workflows

RelatoKit is designed for coding agents preparing useful Feedback Assistant
reports. Its stable workflow uses Apple's native macOS app. The experimental
`web` command family provides read-only access to Apple's undocumented
Feedback Assistant web service after an explicit Apple Account login.

Agent workflow:
  1. Research the issue and write any supporting evidence to a local file.
  2. Run `relato prepare` to create the payload pair:
       feedback-submission.json  machine-readable contract for relato
       feedback-submission.md    human-readable report for review/logs
  3. Inspect the Markdown and JSON before touching the native app.
  4. Run `relato submit --dry-run --select-popups --payload feedback-submission.json`.
  5. Run `relato submit --select-popups --payload feedback-submission.json`
     to open, fill, and select known native popups without submitting.
  6. Inspect Feedback Assistant for native-only fields, diagnostics, and files.
  7. Only after explicit user confirmation, run with `--confirm`.
  8. Use `relato store list` and `relato store uploads` as local evidence.

Commands:
  relato version
  relato store summary [--db PATH]
  relato store list [--limit N] [--db PATH]
  relato store uploads [--limit N] [--db PATH]
  relato categories [--db PATH]
  relato categorize --title TEXT [--description TEXT] [--bundle-id ID]
  relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]
  relato routes
  relato open ROUTE [--id ID] [--print-only]
  relato open-native [--payload PATH]
  relato fill [--payload PATH] [--select-popups]
  relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]
  relato web auth login --apple-id EMAIL [--two-factor-code-command COMMAND]
  relato web auth status
  relato web auth logout
  relato web inbox list [--locale LOCALE] [--team-id ID] [--compact]
  relato web forms list [--locale LOCALE] [--team-id ID] [--compact]
  relato web forms view --id ID [--locale LOCALE] [--team-id ID] [--compact]

Help topics:
  relato help payload
  relato help prepare
  relato help submit
  relato help fill
  relato help store
  relato help web

Safety:
  `--confirm` presses the native Submit button through Accessibility. It is not headless
  submission and local store verification is not an Apple server receipt.
  Native form automation uses an Objective-C Accessibility engine with passive
  AX value writes for fields and AX menu actions for requested popup selection.
  Feedback Assistant is opened without activation. `--select-popups` briefly
  activates it for menu selection, and the app is hidden after launch/fill.
  Snapshot attachments are staged into the local Feedback Assistant draft
  folder in the background after the native draft exists.

  `relato web` is unofficial, read-only, and isolated from the stable native
  workflow. Its endpoints may change without notice. It does not create drafts,
  upload files, or submit feedback.
```

To regenerate:

```sh
make generate-command-docs
```

## Commands

- `relato version`
- `relato store summary [--db PATH]`
- `relato store list [--limit N] [--db PATH]`
- `relato store uploads [--limit N] [--db PATH]`
- `relato categories [--db PATH]`
- `relato categorize --title TEXT [--description TEXT] [--bundle-id ID]`
- `relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]`
- `relato routes`
- `relato open ROUTE [--id ID] [--print-only]`
- `relato open-native [--payload PATH]`
- `relato fill [--payload PATH] [--select-popups]`
- `relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]`
- `relato web auth login --apple-id EMAIL [--two-factor-code-command COMMAND]`
- `relato web auth status`
- `relato web auth logout`
- `relato web inbox list [--locale LOCALE] [--team-id ID] [--compact]`
- `relato web forms list [--locale LOCALE] [--team-id ID] [--compact]`
- `relato web forms view --id ID [--locale LOCALE] [--team-id ID] [--compact]`

## Topic Help

### `relato help payload`

```sh
relato prepare: create the payload pair agents should review and reuse

Usage:
  relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]

Outputs:
  feedback-submission.json
    Machine-readable payload consumed by `open-native`, `fill`, and `submit`.
    Keep this file as the source of truth for the native handoff.

  feedback-submission.md
    Human-readable review artifact. Use it in agent logs, PR notes, or as an
    attachment when useful.

Options:
  --title TEXT          Feedback title.
  --description TEXT    Full report body. Preserve real newlines.
  --snapshot PATH       Local evidence attachment. This can be a screenshot,
                        Markdown note, log, sysdiagnose pointer, or sample file.
  --bundle-id ID        App bundle ID when relevant.
  --platform VALUE      Native platform label. Inferred from the title and
                        description when omitted.
                        Values: iOS, iPadOS, Mac Catalyst, macOS, tvOS,
                        visionOS, watchOS, or Web & Services.
  --kind VALUE          bug or suggestion. Defaults to bug.
  --output-dir DIR      Where to write the JSON and Markdown files.

Agent pattern:
  relato prepare \
    --title "Foundation Models framework: add first-class video input support" \
    --description "$REPORT_BODY" \
    --snapshot ./evidence.md \
    --kind suggestion \
    --output-dir /tmp/relato-report

  sed -n '1,220p' /tmp/relato-report/feedback-submission.md
  relato submit --payload /tmp/relato-report/feedback-submission.json --dry-run
```

### `relato help prepare`

```sh
relato prepare: create the payload pair agents should review and reuse

Usage:
  relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]

Outputs:
  feedback-submission.json
    Machine-readable payload consumed by `open-native`, `fill`, and `submit`.
    Keep this file as the source of truth for the native handoff.

  feedback-submission.md
    Human-readable review artifact. Use it in agent logs, PR notes, or as an
    attachment when useful.

Options:
  --title TEXT          Feedback title.
  --description TEXT    Full report body. Preserve real newlines.
  --snapshot PATH       Local evidence attachment. This can be a screenshot,
                        Markdown note, log, sysdiagnose pointer, or sample file.
  --bundle-id ID        App bundle ID when relevant.
  --platform VALUE      Native platform label. Inferred from the title and
                        description when omitted.
                        Values: iOS, iPadOS, Mac Catalyst, macOS, tvOS,
                        visionOS, watchOS, or Web & Services.
  --kind VALUE          bug or suggestion. Defaults to bug.
  --output-dir DIR      Where to write the JSON and Markdown files.

Agent pattern:
  relato prepare \
    --title "Foundation Models framework: add first-class video input support" \
    --description "$REPORT_BODY" \
    --snapshot ./evidence.md \
    --kind suggestion \
    --output-dir /tmp/relato-report

  sed -n '1,220p' /tmp/relato-report/feedback-submission.md
  relato submit --payload /tmp/relato-report/feedback-submission.json --dry-run
```

### `relato help submit`

```sh
relato submit: open/fill Feedback Assistant and optionally click native Submit

Usage:
  relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]

Default behavior:
  Without `--confirm`, this fills the native form from the JSON payload, hides
  the app, and stops before Submit. Without `--select-popups`, Feedback Assistant
  is opened without activation. Popup selection briefly activates the app.

Confirmation:
  --confirm             Presses the native Submit button through
                        Accessibility automation. Use only after explicit
                        user confirmation at action time.

Verification:
  --verify-store        Reads the local Feedback Assistant store before/after
                        the handoff and prints local deltas.
  --db PATH             Override the local Feedback Assistant SQLite path.
  --dry-run             Print the planned native handoff without opening,
                        filling, attaching, or submitting.

Native form reality:
  Apple can add topic-specific required fields, popups, diagnostics, or log
  gathering. Agents should inspect the native app before `--confirm`; the
  local store check is useful evidence but not a server-side receipt.
  RelatoKit uses an Objective-C Accessibility engine for native UI automation.
  Text fields are set through passive AX value writes. With `--select-popups`,
  native platform, area, and type menus are selected through AX actions.
  Snapshot attachments are staged into the local Feedback Assistant draft folder after the native draft
  exists, avoiding the Add Attachment picker. Popup selection briefly activates
  Feedback Assistant and fails closed if the requested native option is absent.

Agent pattern:
  relato submit --payload feedback-submission.json --select-popups --dry-run
  relato submit --payload feedback-submission.json --select-popups
  # inspect native UI and satisfy any remaining Apple-only fields
  relato submit --payload feedback-submission.json --select-popups --confirm --verify-store
  relato store list --limit 10
  relato store uploads --limit 10
```

### `relato help fill`

```sh
relato fill: fill the currently open Feedback Assistant draft

Usage:
  relato fill [--payload PATH] [--select-popups]

Notes:
  This does not open a new route and does not submit. It is useful when an
  agent has already navigated the native app, manually selected a topic, or
  needs to retry form fill after changing native-only fields.

  --select-popups asks the AX driver to select known platform, area, and type
  popups. Feedback Assistant is briefly activated for menu selection, then hidden.
```

### `relato help store`

```sh
relato store: inspect the local Feedback Assistant store

Usage:
  relato store summary [--db PATH]
  relato store list [--limit N] [--db PATH]
  relato store uploads [--limit N] [--db PATH]

Agent pattern:
  relato store summary
  relato store list --limit 10
  relato store uploads --limit 10

Notes:
  Store reads are local evidence only. They can show drafts, recent items,
  and upload tasks, but they are not Apple server receipts.
```

### `relato help web`

```sh
relato web: experimental read-only Feedback Assistant web access

Status:
  EXPERIMENTAL / UNOFFICIAL / READ-ONLY

This command family uses Apple's undocumented Appleseed web service. It is
separate from the public App Store Connect API and from ASC's private Iris API.
Endpoints and response schemas can change without notice.

Authentication:
  relato web auth login --apple-id EMAIL [--two-factor-code-command COMMAND]
    Performs Apple Account SRP authentication directly from Swift. The password
    is read from a secure terminal prompt by default and is never stored.
    Trusted-device and trusted-phone two-factor challenges are supported.
    RelatoKit stores the resulting cookies and a one-way account hash in Keychain.

  relato web auth status
    Validates the cached session against Feedback Assistant.

  relato web auth logout
    Deletes the local Keychain session. It does not revoke Apple sessions.

Login options and environment:
  --apple-id EMAIL
    Apple Account email. Defaults to RELATO_WEB_APPLE_ID.

  --two-factor-code-command COMMAND
    Runs COMMAND for each requested verification code and reads the code from
    stdout. Defaults to RELATO_WEB_2FA_CODE_COMMAND. Without a command, an
    interactive terminal prompt is used.

  RELATO_WEB_PASSWORD
    Supplies the password non-interactively. A secure terminal prompt is safer
    for human use because environment variables may be exposed to child
    processes or shell tooling.

Headless boundary:
  Password-based Apple Accounts, including trusted-device and trusted-phone 2FA,
  can authenticate without WebKit, Chrome, or the ASC binary. Passkey-only
  accounts and Apple Account actions that require a browser are not supported.

Read-only commands:
  relato web inbox list [--locale LOCALE] [--team-id ID] [--compact]
  relato web forms list [--locale LOCALE] [--team-id ID] [--compact]
  relato web forms view --id ID [--locale LOCALE] [--team-id ID] [--compact]

Output:
  JSON is pretty-printed by default for agent inspection.
  --compact emits compact JSON.

Boundaries:
  This experiment does not create or edit drafts, upload attachments, answer
  questions, or submit feedback. The stable native workflow is unchanged.
```

## Scripting Tips

- Use `relato submit --dry-run` before `--confirm` to preview the native handoff plan.
- Treat the JSON payload as the source of truth; regenerate it instead of hand-editing unless you know the schema.
- Use the Markdown payload to review the report body and stage supporting evidence.
- Use `relato open ROUTE --print-only` when you only need the Feedback Assistant URL.
- Use `relato store summary` and `relato store list` for local verification after native submission.
- Treat local store verification as local evidence, not an Apple server receipt.
- `--select-popups` briefly activates Feedback Assistant to select native platform, area, and type menus.
- Use `relato web auth status` before experimental read-only web requests.
- Treat `relato web` response schemas as unstable and preserve raw JSON when debugging.
