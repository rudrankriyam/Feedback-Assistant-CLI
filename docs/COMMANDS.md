# Command Reference

This file is generated from live CLI help output. xcfb is optimized for agent-driven Feedback Assistant workflows.

## Agent Flow

1. Research the issue and write supporting evidence to a local file.
2. Run `xcfb prepare` to create `feedback-submission.json` and `feedback-submission.md`.
3. Inspect both files before touching the native app.
4. Run `xcfb submit --dry-run --select-popups --payload feedback-submission.json`.
5. Run `xcfb submit --select-popups --payload feedback-submission.json` to fill safe fields, select known native popups, stage attachments, and stop before Submit.
6. Inspect Feedback Assistant for native-only fields, popups, diagnostics, and staged attachments.
7. Use `--confirm` only after explicit user confirmation.
8. Use `xcfb store list` and `xcfb store uploads` as local evidence afterward; they are not Apple server receipts.
9. Keep `xcfb web` isolated as an experimental server-backed workflow; require `--confirm` for submission.

## Payload Contract

- `feedback-submission.json` is the machine-readable contract used by `open-native`, `fill`, and `submit`.
- `feedback-submission.md` is the human-readable review artifact for logs, notes, or attachments.
- `--snapshot PATH` can point to any local evidence file, not only an image.
- `--platform PLATFORM` records the native platform popup value; it is inferred from the report when omitted.

## Global Help

```sh
xcfb: agent-first tooling for Apple Feedback Assistant workflows

xcfb is designed for coding agents preparing useful Feedback Assistant
reports. Its stable workflow uses Apple's native macOS app. The experimental
`web` command family provides headless access to Apple's undocumented
Feedback Assistant web service after an explicit Apple Account login.

Agent workflow:
  1. Research the issue and write any supporting evidence to a local file.
  2. Run `xcfb prepare` to create the payload pair:
       feedback-submission.json  machine-readable contract for xcfb
       feedback-submission.md    human-readable report for review/logs
  3. Inspect the Markdown and JSON before touching the native app.
  4. Run `xcfb submit --dry-run --select-popups --payload feedback-submission.json`.
  5. Run `xcfb submit --select-popups --payload feedback-submission.json`
     to open, fill, and select known native popups without submitting.
  6. Inspect Feedback Assistant for native-only fields, diagnostics, and files.
  7. Only after explicit user confirmation, run with `--confirm`.
  8. Use `xcfb store list` and `xcfb store uploads` as local evidence.

Commands:
  xcfb version
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

Help topics:
  xcfb help payload
  xcfb help prepare
  xcfb help submit
  xcfb help fill
  xcfb help store
  xcfb help web

Safety:
  `--confirm` presses the native Submit button through Accessibility. It is not headless
  submission and local store verification is not an Apple server receipt.
  Native form automation uses an Objective-C Accessibility engine with passive
  AX value writes for fields and AX menu actions for requested popup selection.
  Feedback Assistant is opened without activation. `--select-popups` briefly
  activates it for menu selection, and the app is hidden after launch/fill.
  Snapshot attachments are staged into the local Feedback Assistant draft
  folder in the background after the native draft exists.

  `xcfb web` is unofficial and isolated from the stable native workflow.
  Its endpoints may change without notice. Draft creation, inspection, and
  schema-validated answer updates are supported. Attachment upload uses
  Apple's file-promise protocol and verifies the result from the draft.
  Confirmed submission verifies the resulting feedback ID through Apple's
  feedback-detail endpoint.
```

To regenerate:

```sh
make generate-command-docs
```

## Commands

- `xcfb version`
- `xcfb store summary [--db PATH]`
- `xcfb store list [--limit N] [--db PATH]`
- `xcfb store uploads [--limit N] [--db PATH]`
- `xcfb categories [--db PATH]`
- `xcfb categorize --title TEXT [--description TEXT] [--bundle-id ID]`
- `xcfb prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]`
- `xcfb routes`
- `xcfb open ROUTE [--id ID] [--print-only]`
- `xcfb open-native [--payload PATH]`
- `xcfb fill [--payload PATH] [--select-popups]`
- `xcfb submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]`
- `xcfb web auth login --apple-id EMAIL [--two-factor-code-command COMMAND]`
- `xcfb web auth status`
- `xcfb web auth logout`
- `xcfb web inbox list [--locale LOCALE] [--team-id ID] [--compact]`
- `xcfb web feedback view --id ID [--locale LOCALE] [--compact]`
- `xcfb web feedback status --id ID [--locale LOCALE] [--compact]`
- `xcfb web forms list [--locale LOCALE] [--team-id ID] [--compact]`
- `xcfb web forms view --id ID [--locale LOCALE] [--team-id ID] [--compact]`
- `xcfb web forms options --id ID [--tat TAT] [--locale LOCALE] [--team-id ID] [--compact]`
- `xcfb web drafts create --form-id ID [--locale LOCALE] [--team-id ID] [--compact]`
- `xcfb web drafts view --id ID [--locale LOCALE] [--compact]`
- `xcfb web drafts update --id ID [--payload PATH] [field options] [--answer TAT=VALUE]... [--locale LOCALE] [--compact]`
- `xcfb web drafts attach --id ID [--file PATH]... [--payload PATH] [--locale LOCALE] [--compact]`
- `xcfb web drafts validate --id ID [--locale LOCALE] [--compact]`
- `xcfb web drafts submit --id ID --confirm [--locale LOCALE] [--compact]`

## Topic Help

### `xcfb help payload`

```sh
xcfb prepare: create the payload pair agents should review and reuse

Usage:
  xcfb prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]

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
  xcfb prepare \
    --title "Foundation Models framework: add first-class video input support" \
    --description "$REPORT_BODY" \
    --snapshot ./evidence.md \
    --kind suggestion \
    --output-dir /tmp/xcfb-report

  sed -n '1,220p' /tmp/xcfb-report/feedback-submission.md
  xcfb submit --payload /tmp/xcfb-report/feedback-submission.json --dry-run
```

### `xcfb help prepare`

```sh
xcfb prepare: create the payload pair agents should review and reuse

Usage:
  xcfb prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--platform PLATFORM] [--kind bug|suggestion] [--output-dir DIR]

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
  xcfb prepare \
    --title "Foundation Models framework: add first-class video input support" \
    --description "$REPORT_BODY" \
    --snapshot ./evidence.md \
    --kind suggestion \
    --output-dir /tmp/xcfb-report

  sed -n '1,220p' /tmp/xcfb-report/feedback-submission.md
  xcfb submit --payload /tmp/xcfb-report/feedback-submission.json --dry-run
```

### `xcfb help submit`

```sh
xcfb submit: open/fill Feedback Assistant and optionally click native Submit

Usage:
  xcfb submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]

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
  xcfb uses an Objective-C Accessibility engine for native UI automation.
  Text fields are set through passive AX value writes. With `--select-popups`,
  native platform, area, and type menus are selected through AX actions.
  Snapshot attachments are staged into the local Feedback Assistant draft folder after the native draft
  exists, avoiding the Add Attachment picker. Popup selection briefly activates
  Feedback Assistant and fails closed if the requested native option is absent.

Agent pattern:
  xcfb submit --payload feedback-submission.json --select-popups --dry-run
  xcfb submit --payload feedback-submission.json --select-popups
  # inspect native UI and satisfy any remaining Apple-only fields
  xcfb submit --payload feedback-submission.json --select-popups --confirm --verify-store
  xcfb store list --limit 10
  xcfb store uploads --limit 10
```

### `xcfb help fill`

```sh
xcfb fill: fill the currently open Feedback Assistant draft

Usage:
  xcfb fill [--payload PATH] [--select-popups]

Notes:
  This does not open a new route and does not submit. It is useful when an
  agent has already navigated the native app, manually selected a topic, or
  needs to retry form fill after changing native-only fields.

  --select-popups asks the AX driver to select known platform, area, and type
  popups. Feedback Assistant is briefly activated for menu selection, then hidden.
```

### `xcfb help store`

```sh
xcfb store: inspect the local Feedback Assistant store

Usage:
  xcfb store summary [--db PATH]
  xcfb store list [--limit N] [--db PATH]
  xcfb store uploads [--limit N] [--db PATH]

Agent pattern:
  xcfb store summary
  xcfb store list --limit 10
  xcfb store uploads --limit 10

Notes:
  Store reads are local evidence only. They can show drafts, recent items,
  and upload tasks, but they are not Apple server receipts.
```

### `xcfb help web`

```sh
xcfb web: experimental Feedback Assistant web access

Status:
  EXPERIMENTAL / UNOFFICIAL

This command family uses Apple's undocumented Appleseed web service. It is
separate from the public App Store Connect API and from ASC's private Iris API.
Endpoints and response schemas can change without notice.

Authentication:
  xcfb web auth login --apple-id EMAIL [--two-factor-code-command COMMAND]
    Performs Apple Account SRP authentication directly from Swift. The password
    is read from a secure terminal prompt by default and is never stored.
    Trusted-device and trusted-phone two-factor challenges are supported.
    xcfb stores only the resulting cookies and a one-way account hash.

  xcfb web auth status
    Validates the cached session against Feedback Assistant.

  xcfb web auth logout
    Deletes the local session from the selected backend. It does not revoke
    Apple sessions.

Login options and environment:
  --apple-id EMAIL
    Apple Account email. Defaults to XCFB_WEB_APPLE_ID.

  --two-factor-code-command COMMAND
    Runs COMMAND for each requested verification code and reads the code from
    stdout. Defaults to XCFB_WEB_2FA_CODE_COMMAND. Without a command, an
    interactive terminal prompt is used.

  XCFB_WEB_PASSWORD
    Supplies the password non-interactively. A secure terminal prompt is safer
    for human use because environment variables may be exposed to child
    processes or shell tooling.

  XCFB_WEB_SESSION_BACKEND
    Selects file or keychain session storage. The default is file, which avoids
    recurring Keychain approval prompts for locally rebuilt unsigned binaries.

  XCFB_WEB_SESSION_DIR
    Overrides the file session directory. The default is ~/.xcfb/web.
    xcfb enforces directory mode 0700 and session file mode 0600.

Headless boundary:
  Password-based Apple Accounts, including trusted-device and trusted-phone 2FA,
  can authenticate without WebKit, Chrome, or the ASC binary. Passkey-only
  accounts and Apple Account actions that require a browser are not supported.

Inspection commands:
  xcfb web inbox list [--locale LOCALE] [--team-id ID] [--compact]
  xcfb web feedback view --id ID [--locale LOCALE] [--compact]
    Reads Apple's server-backed feedback detail envelope, including the
    submitted feedback ID and originating form-response ID.

  xcfb web feedback status --id ID [--locale LOCALE] [--compact]
    Reads Apple's current status rows for a submitted feedback report.

  xcfb web forms list [--locale LOCALE] [--team-id ID] [--compact]
  xcfb web forms view --id ID [--locale LOCALE] [--team-id ID] [--compact]
  xcfb web forms options --id ID [--tat TAT] [--locale LOCALE] [--team-id ID] [--compact]
    Emits normalized question metadata and label/value pairs. Use --tat to
    inspect one semantic field, such as :platform or :area.

Draft commands:
  xcfb web drafts create --form-id ID [--locale LOCALE] [--team-id ID] [--compact]
    Creates a server-backed draft for a form returned by `web forms list`.
    The Apple response, including the new form response ID, is emitted as JSON.

  xcfb web drafts view --id ID [--locale LOCALE] [--compact]
    Reads a server-backed draft, including its form ID, saved answers, and
    attachment records.

  xcfb web drafts update --id ID [--payload PATH] [field options] [--answer TAT=VALUE]... [--locale LOCALE] [--compact]
    Fetches the current draft and form schema, preserves untouched answers,
    resolves choice labels to Apple's values, validates text limits, and saves
    the complete answer set.

    Named field options:
      --title TEXT
      --platform VALUE
      --technology LABEL_OR_VALUE
      --kind bug|suggestion
      --description TEXT
      --app TEXT
      --impact TEXT
      --foundation-models-mode feedback|samples|APPLE_VALUE

    --payload imports title, description, platform, category area, and kind
    from a `xcfb prepare` JSON payload. Explicit named options override it.
    Repeat --answer TAT=VALUE for conditional or form-specific questions.
    Repeating the same TAT supplies multiple checkbox values.

  xcfb web drafts attach --id ID [--file PATH]... [--payload PATH] [--locale LOCALE] [--compact]
    Uploads one or more local files through Apple's file-promise sequence:
    create, mark uploading, obtain a presigned object URL, upload raw bytes,
    mark uploaded, and verify the persisted file promise from the draft.

    Repeat --file to attach multiple files. --payload attaches the snapshot
    path from a `xcfb prepare` JSON payload. Duplicate paths are uploaded once.
    The command emits verified attachment receipts and never prints presigned URLs.

  xcfb web drafts validate --id ID [--locale LOCALE] [--compact]
    Fetches the draft and its current form schema, evaluates Apple's conditional
    required fields, treats an uploaded file promise as satisfying a visible
    Required File Zone, and emits a machine-readable readiness result.

  xcfb web drafts submit --id ID --confirm [--locale LOCALE] [--compact]
    Saves the complete answer set using Apple's submission representation,
    submits the server-backed draft, and verifies the returned feedback ID
    through Apple's feedback-detail endpoint.

    --confirm is required and has no alias. This creates an Apple feedback
    report and must be used only after explicit user confirmation at action time.
    Survey drafts use a different Apple workflow and fail closed.

Output:
  JSON is pretty-printed by default for agent inspection.
  --compact emits compact JSON.

Boundaries:
  This experiment creates, reads, edits, attaches files to, and submits
  server-backed drafts. Survey submission remains unsupported, and the stable
  native workflow is unchanged.
```

## Scripting Tips

- Use `xcfb submit --dry-run` before `--confirm` to preview the native handoff plan.
- Treat the JSON payload as the source of truth; regenerate it instead of hand-editing unless you know the schema.
- Use the Markdown payload to review the report body and stage supporting evidence.
- Use `xcfb open ROUTE --print-only` when you only need the Feedback Assistant URL.
- Use `xcfb store summary` and `xcfb store list` for local verification after native submission.
- Treat local store verification as local evidence, not an Apple server receipt.
- `--select-popups` briefly activates Feedback Assistant to select native platform, area, and type menus.
- Use `xcfb web auth status` before experimental web requests.
- Treat `xcfb web` response schemas as unstable and preserve raw JSON when debugging.
