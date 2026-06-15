#!/usr/bin/env python3
"""Generate docs/COMMANDS.md from live `xcfb --help` output."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "docs" / "COMMANDS.md"


HELP_TOPICS = ["payload", "prepare", "submit", "fill", "store", "web"]


def run_xcfb_help(*args: str) -> str:
    proc = subprocess.run(
        ["swift", "run", "xcfb", *args],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return proc.stdout or proc.stderr


def run_help_text() -> str:
    return run_xcfb_help("--help")


def parse_commands(help_text: str) -> list[str]:
    commands: list[str] = []
    in_commands = False
    for line in help_text.splitlines():
        stripped = line.strip()
        if stripped == "Commands:":
            in_commands = True
            continue
        if in_commands and stripped.startswith("xcfb "):
            commands.append(stripped)
            continue
        if in_commands and commands and not stripped:
            break
    return commands


def render(commands: list[str], global_help: str, topic_help: dict[str, str]) -> str:
    lines = [
        "# Command Reference",
        "",
        "This file is generated from live CLI help output. xcfb is optimized for agent-driven Feedback Assistant workflows.",
        "",
        "## Agent Flow",
        "",
        "1. Research the issue and write supporting evidence to a local file.",
        "2. Run `xcfb prepare` to create `feedback-submission.json` and `feedback-submission.md`.",
        "3. Inspect both files before touching the native app.",
        "4. Run `xcfb submit --dry-run --select-popups --payload feedback-submission.json`.",
        "5. Run `xcfb submit --select-popups --payload feedback-submission.json` to fill safe fields, select known native popups, stage attachments, and stop before Submit.",
        "6. Inspect Feedback Assistant for native-only fields, popups, diagnostics, and staged attachments.",
        "7. Use `--confirm` only after explicit user confirmation.",
        "8. Use `xcfb store list` and `xcfb store uploads` as local evidence afterward; they are not Apple server receipts.",
        "9. Keep `xcfb web` isolated as an experimental server-backed workflow; require `--confirm` for submission.",
        "",
        "## Payload Contract",
        "",
        "- `feedback-submission.json` is the machine-readable contract used by `open-native`, `fill`, and `submit`.",
        "- `feedback-submission.md` is the human-readable review artifact for logs, notes, or attachments.",
        "- `--snapshot PATH` can point to any local evidence file, not only an image.",
        "- `--platform PLATFORM` records the native platform popup value; it is inferred from the report when omitted.",
        "",
        "## Global Help",
        "",
        "```sh",
        global_help.rstrip(),
        "```",
        "",
        "To regenerate:",
        "",
        "```sh",
        "make generate-command-docs",
        "```",
        "",
        "## Commands",
        "",
    ]
    for command in commands:
        lines.append(f"- `{command}`")
    lines.extend(
        [
            "",
            "## Topic Help",
            "",
        ]
    )
    for topic, help_text in topic_help.items():
        lines.extend(
            [
                f"### `xcfb help {topic}`",
                "",
                "```sh",
                help_text.rstrip(),
                "```",
                "",
            ]
        )
    lines.extend(
        [
            "## Scripting Tips",
            "",
            "- Use `xcfb submit --dry-run` before `--confirm` to preview the native handoff plan.",
            "- Treat the JSON payload as the source of truth; regenerate it instead of hand-editing unless you know the schema.",
            "- Use the Markdown payload to review the report body and stage supporting evidence.",
            "- Use `xcfb open ROUTE --print-only` when you only need the Feedback Assistant URL.",
            "- Use `xcfb store summary` and `xcfb store list` for local verification after native submission.",
            "- Treat local store verification as local evidence, not an Apple server receipt.",
            "- `--select-popups` briefly activates Feedback Assistant to select native platform, area, and type menus.",
            "- Use `xcfb web auth status` before experimental web requests.",
            "- Treat `xcfb web` response schemas as unstable and preserve raw JSON when debugging.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate docs/COMMANDS.md from live CLI help")
    parser.add_argument("--check", action="store_true", help="Fail if docs/COMMANDS.md is out of date")
    args = parser.parse_args()

    global_help = run_help_text()
    topic_help = {topic: run_xcfb_help("help", topic) for topic in HELP_TOPICS}
    generated = render(parse_commands(global_help), global_help, topic_help)

    if args.check:
        current = OUTPUT_PATH.read_text() if OUTPUT_PATH.exists() else ""
        if current != generated:
            print("docs/COMMANDS.md is out of date.")
            print("Run: make generate-command-docs")
            return 1
        print("docs/COMMANDS.md is up to date.")
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(generated)
    print(f"Generated {OUTPUT_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
