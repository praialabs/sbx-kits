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

### Verified in `agy 1.5.16` (via ELF Go reflection metadata, changelog & live `-p "/quota"`)
* **Cost Structure (`types.StatusLineCost`)**:
  - Defined in Go as `{ total_usd: float64, subagent_usd: float64, estimated: bool }`, omitted (`omitempty`) under flat subscription plans (e.g. Google AI Pro).
  - Intentionally not parsed or rendered by `statusline.sh`.
* **VCS Branch & Dirty Omission (`types.StatusLineVCS`)**:
  - Defines `type`, `branch`, `client`, and `dirty` struct tags, though AGY may still only emit `vcs: {"type": "git"}` without `branch` or `dirty` at runtime.
  - The script maintains an on-disk fallback (`git rev-parse --abbrev-ref HEAD` and `git status --porcelain`) when `.vcs.branch` is empty so branch name and dirty indicator (`*`) are reliably displayed.
* **Quota Buckets (`types.StatusLineQuotaBucket`) & Limiting Factor Heuristic**:
  - Each bucket contains `remaining_fraction` (`*float32`), `remaining_amount` (`*int64`), `reset_time` (`*time.Time`), `reset_in_seconds` (`*int64`), and `disabled` (`bool`).
  - As of `agy 1.5.16`, Argon models (`Gemini 4 Argon`, `Orchestrator (Argon)`) are back in the unified `Gemini Models` group — the temporary `gemini-argon-wtu-weekly` bucket is gone.
  - Four quota buckets are emitted across 2 quota families (`g`, `3p`):
    - `gemini-5h`, `gemini-weekly` (`g:●·●`)
    - `3p-5h`, `3p-weekly` (`3p:●·●`)
  - Under `GEMINI_API_KEY` connections (since `1.5.11`), `.quota` is omitted/empty; the script hides the quota segment cleanly when `.quota` is empty, and renders a dim `–` for `disabled: true` buckets.
  - Since `agy 1.5.16`, quota is also refreshed periodically during long streaming turns (>1 min).
  - To prevent ambiguity between the 5h rolling window and the weekly ceiling, timers are prefixed (`5h:1h30m` or `wk:2d2h`).
  - **Limiting Factor Heuristic**:
    1. *Healthy Suppression*: If both 5h and weekly are $\ge 85\%$, omit the timer to keep the bar clean.
    2. *Weekly Critical*: If weekly is $\le 20\%$, always show `(wk:...)` as it represents a multi-day lockout risk.
    3. *Constrained Bucket*: Compare 5h vs weekly remaining percentages and display the timer for the lower bucket (or 5h when equal).
* **Model Display Name & Effort (`types.StatusLineModelInfo`)**:
  - Defines `id`, `display_name`, and `effort`.
  - Since `1.5.14`, `Orchestrator` models include the planner in parentheses (e.g. `Orchestrator (Argon)`). Only strip known effort suffixes (`Low`, `Medium`, `High`, `XHigh`, `Max`, `Minimal`, `Thinking`) so planner names are preserved.
* **Other Notable `StatusLineData` / `StatusLineConfig` Fields (in `agy 1.5.16`)**:
  - `StatusLineSubagent` gained a `model` field in `1.5.3` (`name`, `role`, `model`, `status`).
  - `StatusLineConfig` supports `stack_with_default` (`bool`) and `padding` (`int`).
  - Full `StatusLineData` also exposes `cycle_mode`, `sandbox` (`enabled`, `allow_network`), `artifact_count`, `plan_tier`, `pending_input_count`, `tool_confirmation_pending`, `task_count`, `battle`, and `vim`.
* **Direct `stdin` Parsing with Process Substitution**:
  - In standard operation, `jq` reads directly from `stdin` with zero intermediate processes.
  - In debug mode, `exec < <(tee "$DEBUG_FILE")` conditionally redirects `stdin` through `tee` before reaching `jq`.

### Fast Verification Commands (Zero Quota Cost)
Before binary inspection, query AGY's live non-interactive print commands (they do not start a turn or spend quota):
```bash
agy --version
agy -p "/quota" --output-format json | jq .
agy -p "/model" --output-format json | jq .
agy -p "/changelog" | awk '/^## <prev-version>/{exit} {print}'
```

### Why Python Binary Inspection instead of `go tool`
Google's release binaries for `agy` are stripped of standard ELF symbol tables (`.symtab`), causing `go tool nm` and `go tool objdump` to fail. However, Go runtime reflection metadata lives intact in `.data.rel.ro` (relocated via `.rela.dyn` with `R_AARCH64_RELATIVE` = 1027 on arm64 or `R_X86_64_RELATIVE` = 8 on x86_64, with `moduledata.types` at `.go.module+0x128`).

Future agents can dump exact `types.StatusLine*` Go struct definitions (field names, types, and JSON tags) with:
```bash
python3 -c '
import shutil, struct, re
data = open(shutil.which("agy"), "rb").read()
e_shoff = struct.unpack_from("<Q", data, 40)[0]
e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 58)
shstr_off = struct.unpack_from("<Q", data, e_shoff + e_shstrndx * e_shentsize + 24)[0]
secs = {}
for i in range(e_shnum):
    n, _, _, a, o, s = struct.unpack_from("<IIQQQQ", data, e_shoff + i * e_shentsize)
    secs[data[shstr_off+n:data.find(b"\x00", shstr_off+n)].decode()] = (a, o, s)
relro_a, relro_o, relro_s = secs[".data.rel.ro"]
rd_a, rd_o, rd_s = secs[".rela.dyn"]
gm_a, gm_o, gm_s = secs[".go.module"]
relocs = {}
for off in range(rd_o, rd_o + rd_s, 24):
    ro, ri, ra = struct.unpack_from("<QQq", data, off)
    if (ri & 0xffffffff) in (8, 1027):
        relocs[ro] = ra
types_base = relocs[gm_a + 0x128]
def v2o(va):
    for a, o, s in secs.values():
        if a <= va < a + s and o > 0: return o + (va - a)
def rptr(va): return relocs.get(va, struct.unpack_from("<Q", data, v2o(va))[0])
def rname(off):
    fl, p, n, sh = data[off], off+1, 0, 0
    while True:
        b = data[p]; p += 1; n |= (b & 0x7f) << sh
        if not (b & 0x80): break
        sh += 7
    nm = data[p:p+n].decode("utf-8", "ignore"); tg = None
    if fl & 2:
        p += n; tn, sh = 0, 0
        while True:
            b = data[p]; p += 1; tn |= (b & 0x7f) << sh
            if not (b & 0x80): break
            sh += 7
        tg = data[p:p+tn].decode("utf-8", "ignore")
    return nm, tg
relro = data[relro_o:relro_o+relro_s]
seen = set()
for m in re.finditer(rb"\*?types\.StatusLine[A-Za-z0-9_]*", relro):
    tok = m.group().decode()
    for d in (2, 3):
        nm, _ = rname(relro_o + m.start() - d)
        if nm == tok:
            srel = (relro_a + m.start() - d) - types_base
            for m2 in re.finditer(re.escape(struct.pack("<i", srel)), relro):
                tr = m2.start() - 40
                if tr >= 0 and tr % 8 == 0 and (data[relro_o+tr+23] & 0x1f) == 25:
                    fva = rptr(relro_a+tr+56); flen, fcap = struct.unpack_from("<QQ", data, relro_o+tr+64)
                    clean = tok.lstrip("*")
                    if flen == fcap and 0 <= flen < 100 and clean not in seen:
                        seen.add(clean); print(f"type {clean} struct {{")
                        for fi in range(flen):
                            fn, ftg = rname(v2o(rptr(fva+fi*24)))
                            fto = v2o(rptr(fva+fi*24+8))
                            ftn, _ = rname(v2o(types_base + struct.unpack_from("<i", data, fto+40)[0]))
                            if (data[fto+20] & 2) and ftn.startswith("*"): ftn = ftn[1:]
                            print(f"  {fn} {ftn}" + (f" `{ftg}`" if ftg else ""))
                        print("}\n")
            break
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
