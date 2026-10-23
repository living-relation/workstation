---
name: harness-design
description: Use when creating, editing, checking, or uploading harness.design wiring harness files (.harness / .harnesslib), working with the harness.design desktop app, MCP tools (create_harness, set_document_json), part libraries, signals/nets, or schematic and layout views. Covers the live local-file workflow, optional cloud upload, library sync, signal propagation, view conventions and known app quirks. Applies to any project; the ST185 repo adds its own rules on top (see st185-build-harness-from-sot).
---

# harness-design

## Precedence
The harness.design docs and tutorials (https://docs.harness.design) win on drawing conventions and best practice. Read the relevant page before drawing. If one of Dan's rules conflicts with the docs: do not pick silently. Flag it, log it in the repo's one tracker (ST185: `docs/OPEN-ITEMS.md`) with both sides and the doc link, and ask/report to Dan. Dan's own drawing rules are owned by the ST185 repo, `docs/harness/redesign/DECISIONS.md` "Binding rules from Daniel" R41-R50 (also his clean-drawing, shared-connector and signal rules) - this skill is the app mechanics and only points at them.

Key pages: /feature/desktop, /feature/part-libraries, /feature/signals, /feature/pinouts, /feature/local-files/json-format, /files/harness/editing-guide.md (also positioning.md, notes.md linked from it).

## Drawings stay clean

- Rule R44 / R49 (ST185 DECISIONS): only parts Dan asked for, nothing "not used", no added coverings / sleeves / extra splices, no unused part definitions; Dan's saved file wins - change the gate, not his drawing.

## 1. Desktop live-file workflow (default)
- The desktop app opens local `.harness` files (File > Open, or double-click), saves to the file immediately, and watches it: saved external changes reload at once. Files are pretty-printed JSON (2-space indent, stable key order), so they diff in git.
- Dan edits in the app, then commit. Cloud upload is optional (sharing only).
- **Conflict rule: the version saved to disk wins.** If the app has unsaved edits when an agent saves, the app's edits are discarded. So agents pause while Dan is editing, and ask before writing a file he may have open.
- **Format version: files follow the app's current schema (v1.2 since 2026-10-15).** The app migrates an older file on open and re-saves it, so an old file in git shows up as a rewrite the first time anyone opens it. When the app moves to a new schema, migrate every file in the repo once, exactly as the app does (compare with an app re-save of one file), prove it lossless, and update the readers; never hand-write an old version. Current format: https://docs.harness.design/files/harness/editing-guide.md and /files/harness/schema/v1.2.json. ST185: DECISIONS R111.
- Write files atomically (temp file, then rename) so the app never reads a half-written file. Keep the app's formatting (2-space indent, key order); do not reformat files wholesale. Never change `version`; `$schema`/`$docs` are rewritten by the app; `formboardData` is ignored on open.
- The app silently deletes content that violates its rules when it opens a file, with no warning. Opening the file in the app is the full validation; the schema only checks structure.
- Moving between modes: Export > Local File (cloud to disk), Upload to cloud... (disk to cloud).

## 2. Cloud upload via MCP (only when asked, for sharing)
- Create with `create_harness`, fill with `set_document_json` (whole document in one call), check with `validate_harness`; `edit_document` / `get_document_json` read and patch.
- Title each upload `<name> YYYY-MM-DD`. Never overwrite an older cloud doc unless Dan asks; create a new one.
- Minified JSON is fine for the wire. Do not keep minified copies in git (they go stale when the file is edited in the app).

## 3. Part libraries (`.harnesslib`)
- A library file holds only `*Parts` arrays, `currency`, `"version": 1.2`, `"kind": "library"`.
- Part configurations (connector, terminal, splice, diode, resistor parts) are an ordered `accessories` list of `{id, type, partId, rule?}` (v1.2). Housing accessories (lock, boot, backshell, mount, dust cover, covering) count once per component; contacts, cavity plugs and seals are per-cavity defaults, first matching `rule` wins. Per-cavity `contactPartId` / `cavityPlugPartId` are overrides. v0.9 held single `lockPartId` / `contactPartId` / ... fields instead (https://docs.harness.design/files/harness/part-library.md).
- Link once: Preferences > Part Libraries > Link existing... Keep the `.harnesslib` in version control next to the `.harness` files it serves; it travels with them (same PR). Library changes pulled from git are picked up while the app is open.
- Parts with the same part number in a harness and a library are the same part. A part needs a part number before it can go in a library. A duplicate part number in a harness gives a warning.
- Sync is per library and per part (all properties equal = in sync); push the harness part to the library or pull the library part into the harness. When they differ, the library wins unless Dan says otherwise.
- ST185 no longer uses harness.design (DECISIONS R225); its old library `docs/harness/rebuild/ST185.harnesslib` is frozen.
- Ids: components and parts share one id space per document; existing ids never change.

## 4. Signals / nets
- A signal typed on a cavity or terminal propagates to every empty cavity/terminal on the same net (fills empty ones only). `"propagate": false` stops it. "Make signal global" joins same-named signals on different nets.
- Set an explicit signal where it originates, and an explicit signal with `propagate: false` wherever the name changes (across a device, plug, inline connector or break), so auto-fill never puts the wrong label on the far side. One propagating signal per net. Terminals, flying leads and endpoints do not propagate.
- A net with several signals shows all of them on empty cavities, which is usually a bug.

## 5. Views
- **Schematic** is whatever reads best, often center-out (main connector or module in the middle or top, breakouts around). No overlapping nodes or notes, few crossovers, related circuits grouped, notes to the side, positions on the grid (30 units in ST185).
- **Layout** reads left to right along the physical route: straight trunk, branches off it, no branch doubling back, a length on each bundle segment. Never join separate harnesses in one layout.
- Connectors, terminals, splices, diodes and resistors need `schematicPosition` and/or `layoutPosition`; never set a position on a group (derived from members). Notes need `schematicPosition`.
- **Shared connectors are drawn whole** (rule R10 in ST185 DECISIONS, all projects): the WHOLE connector in every file; cavities another file owns get `"notConnected": true` (no signal, no contact, `"cavityPlugPartId": null` so only the owner counts it) plus a note "see <other file>" (https://docs.harness.design/component/connector "not-connected cavities"). N/C cavities are not conductors, so they do not count toward the Free-plan connection limit (https://docs.harness.design/plan).
- Devices (ECUs, sensors, switches) are not components: model them as harness-side connectors in a group named for the device.
- Deleting a component: also remove wires, mates, bundles and any `partId`/`contactPartId`/`coveringIds` pointing at it. In group documents references use `<groupId>-<localId>`.

## 6. Known quirks
- Unknown keys are rejected (e.g. `physicalPartGroup`, `shield`). Keep repo-only data outside the harness file (ST185: in `docs/harness/MASTER-wirelist.csv`; `interfaces.json` no longer exists).
- Free plan: 100 connections per harness, also for local files.
- The per-wire splice gauge warning is a false alarm.
- Node sizes/heights are not documented, so overlap checks are estimates; look at the drawing in the app.
- Do not hand-write what the app regenerates; rely on opening the file as the final check.

## ST185 repo specifics
ST185 does NOT use harness.design any more (DECISIONS R225, Dan 2026-10-20): its ONE drawing set `ST185-harness` comes from the repo's own generator (`docs/harness/tools/build_drawings.py`) and the master wire list; skill `st185-build-harness-from-sot`. The old harness.design files in `docs/harness/rebuild/` are frozen and will be deleted (OPEN-ITEMS row 153). Do not create or edit ST185 `.harness` files.
