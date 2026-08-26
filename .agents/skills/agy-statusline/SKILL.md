---
name: agy-statusline
description: Develop, debug, test, or preview the Antigravity CLI status line script (statusline.sh). Use when modifying status bar segments, responsive layouts, or inspecting runtime payload data.
---

# AGY Statusline Development & Maintenance Guide

This skill covers how to inspect, debug, update, and verify the custom status line script for the Antigravity CLI (`agy`) located at:
`agents/agy/files/home/.gemini/antigravity-cli/statusline.sh`

---

## 1. AGY Statusline Data Contract & Binary Findings

AGY pipes a single JSON object to the script's `stdin` on every state change.

### Verified in `agy 1.1.21` (via binary inspection)
* **Cost Structure**:
  - Defined in Go as `Cost *types.StatusLineCost `json:"cost,omitempty"``.
  - Under flat subscription plans (e.g. Google AI Pro) or before metered costs accrue, `Cost` is `nil` and the `"cost"` key is **completely omitted** from the JSON payload.
  - When present, `StatusLineCost` contains `.estimated`, `.workspace`, and `.subagents`.
  - Guard with `if .cost != null` in `jq`, and omit the cost display segment when absent to keep the status bar uncluttered.
* **VCS Branch & Dirty Omission**:
  - In `agy 1.1.21`, binary inspection confirms `types.StatusLineVCS` only defines `Type string `json:"type,omitempty"``.
  - AGY only emits `vcs: {"type": "git"}` and does **not** populate `branch` or `dirty` properties in the payload.
  - The script **must** maintain an on-disk fallback (`git rev-parse --abbrev-ref HEAD` and `git status --porcelain`) when `.vcs.branch` is empty so branch name and dirty indicator (`*`) are reliably displayed.
* **Quota Buckets & Limiting Factor Heuristic**:
  - Four quota buckets are provided: `gemini-5h`, `gemini-weekly`, `3p-5h`, `3p-weekly`.
  - Each contains `remaining_fraction` (float 0.0–1.0) and `reset_in_seconds` (integer).
  - To prevent ambiguity between the 5h rolling window and the weekly ceiling, timers are prefixed (`5h:1h30m` or `wk:16h`).
  - **Limiting Factor Heuristic**:
    1. *Healthy Suppression*: If both 5h and weekly are $\ge 85\%$, omit the timer to keep the bar clean.
    2. *Weekly Critical*: If weekly is $\le 20\%$, always show `(wk:...)` as it represents a multi-day lockout risk.
    3. *Constrained Bucket*: Compare 5h vs weekly remaining percentages and display the timer for the lower bucket (or 5h when equal).
* **Direct `stdin` Parsing with Process Substitution**:
  - In standard operation, `jq` reads directly from `stdin` with zero intermediate processes.
  - In debug mode, `exec < <(tee "$DEBUG_FILE")` conditionally redirects `stdin` through `tee` before reaching `jq`.

### Why Python Binary Inspection instead of `go tool`
Google's release binaries for `agy` are stripped of standard ELF symbol tables (`.symtab`) and standard Go buildinfo (`.go.buildinfo`), causing `go tool nm`, `go tool objdump`, and `go version -m` to return `no symbol section` / `not a Go executable`.

However, Go runtime reflection metadata (`.rodata` type descriptors and `pclntab`) remains intact for runtime execution. Future agents can re-verify struct definitions using this Python one-liner:
```bash
python3 -c '
with open("$(which agy)", "rb") as f:
    data = f.read()
import re
for t in [b"StatusLineData", b"StatusLineCost", b"StatusLineVCS", b"StatusLineQuotaBucket"]:
    pos = data.find(b"types." + t)
    if pos != -1:
        print(f"=== types.{t.decode()} ===")
        print(re.sub(rb"[^\x20-\x7e]+", b"\n", data[pos:pos+400]).decode("ascii", "ignore"))
'
```

---

## 2. Debugging & Capturing Live Payloads

To inspect the raw JSON data AGY is sending at runtime:

1. **Launch AGY with the single debug environment variable**:
   ```bash
   # Default: writes to /tmp/agy-statusline-debug.json
   AGY_STATUSLINE_DEBUG=1 agy

   # Or specify a custom output file:
   AGY_STATUSLINE_DEBUG=/path/to/dump.json agy
   ```
2. **Inspect the captured JSON**:
   ```bash
   jq . /tmp/agy-statusline-debug.json
   ```
3. **Zero Overhead**: When `AGY_STATUSLINE_DEBUG` is unset, `jq` reads `stdin` directly with zero file I/O overhead.

---

## 3. Visual Verification Workflow

Always verify rendering across widths using the preview utility before committing changes:

1. **Preview built-in scenarios across column widths (120, 100, 80, 60 cols)**:
   ```bash
   ./tools/preview-statusline.sh
   ```
2. **Preview a live captured debug payload**:
   ```bash
   ./tools/preview-statusline.sh /tmp/agy-statusline-debug.json 80
   ```
3. **Verify Layout Invariants**:
   - Ensure the line never wraps or exceeds the specified terminal width (`PAD >= 0`).
   - Narrow screens ($< 75$ cols) should collapse secondary segments (like branch/effort) gracefully to keep model name and core status visible.

---

## 4. Repository Structure & Sandbox Boundary

* **Sandbox Files (`agents/agy/files/`)**: Only place files that must be deployed into the container image.
* **Development Tooling (`tools/`)**: Keep preview scripts, test harnesses, and dev helpers in `tools/` outside `agents/`.
