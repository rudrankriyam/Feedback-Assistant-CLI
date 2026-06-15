# AX Automation

xcfb uses macOS Accessibility APIs for native Feedback Assistant automation. The native form driver is implemented in Objective-C with `AXUIElement` and fail-closed handling for native controls Feedback Assistant does not expose cleanly.

The AX driver works by:

1. Resolving Feedback Assistant by bundle identifier.
2. Reading windows and descendants from the Accessibility tree.
3. Matching controls by role, title, description, and value.
4. Attempting text fields and text areas through `AXValue`.
5. Using passive `AXValue` writes for text fields.
6. Briefly activating Feedback Assistant when `--select-popups` is requested, then selecting native menu items through AX actions.
7. Avoiding synthetic mouse events, keyboard events, pointer events, and pasteboard writes.
8. Staging local snapshots into the active Feedback Assistant draft folder after the native draft exists.
9. Opening Feedback Assistant without activation for text-only fill and hiding it after launch/fill.
10. Failing closed when a requested popup or menu item is unavailable.
11. Stopping before final submission unless `--confirm` is explicitly provided.

## What AX Can Do

AX can drive many native controls without AppleScript:

- set title and description fields
- set bundle identifier fields when the form exposes them
- choose topic rows
- select platform, technology/area, and feedback-type popups
- press Continue and Submit buttons
- stage local evidence files into Feedback Assistant's local draft folder

## Practical Limits

AX is still native UI automation. It depends on the target app exposing useful Accessibility elements. xcfb intentionally does not synthesize keyboard input, move the pointer, click screen coordinates, or use the pasteboard. Text-only fill stays in the background. Popup selection briefly activates Feedback Assistant because its SwiftUI menus do not expose selectable children while hidden.

If AX mutation fails or a requested menu item is absent, xcfb fails closed and reports the unsupported native-control boundary.

Background-input evaluation covered the techniques used by tools such as [Cua](https://github.com/trycua/cua) and [Peekaboo](https://github.com/openclaw/Peekaboo): hidden window inspection, SkyLight per-PID event posting, focus-without-raise, AX direct value setting, and process-targeted keyboard events. Those techniques can mutate and render hidden Feedback Assistant text fields, but they do not make its SwiftUI popups selectable while hidden. xcfb therefore uses a narrow, explicit foreground step for `--select-popups`, followed by its normal hide behavior.

Cua and Peekaboo are not runtime dependencies. xcfb keeps the native automation implementation local and avoids input-stealing event synthesis.

Some forms do not support every report kind. For example, a macOS form can accept `Incorrect/Unexpected Behavior` while rejecting `Suggestion` for its type popup. In those cases xcfb reports the failing native value instead of pretending the form was completed.

Local file attachments use draft-folder staging. Once Feedback Assistant creates a draft, xcfb copies the snapshot into `~/Library/Group Containers/group.com.apple.feedback/Library/Drafts/FB/<draft-id>/` and prints the staged path. xcfb does not drive the visible Add Attachment > `Choose File...` picker because Feedback Assistant does not reliably open that transient menu while inactive.

For fully isolated automation that never activates Feedback Assistant on the user's primary desktop, omit `--select-popups` and complete native menus manually later, or run the full native workflow in a separate macOS GUI session or virtual machine.
