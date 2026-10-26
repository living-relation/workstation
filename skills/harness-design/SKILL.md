---
name: harness-design
description: Use when creating, editing, checking, or uploading harness.design wiring harness files (.harness / .harnesslib), working with the harness.design desktop app, MCP tools (create_harness, set_document_json), part libraries, signals/nets, or schematic and layout views. Requires a spreadsheet wire list before any harness is built, and covers the order of work, live local-file workflow, optional cloud upload, library sync, signal propagation, view conventions and known app quirks. Applies to any project; a project's own rules (its AGENTS.md / decisions file) win over this skill.
---

# harness-design

## Precedence
The harness.design docs and tutorials (https://docs.harness.design) win on drawing conventions and best practice. Read the relevant page before drawing. If one of the owner's rules conflicts with the docs: do not pick silently. Flag it, log it in the project's one tracker with both sides and the doc link, and ask/report to the owner. The owner's own drawing rules (clean-drawing, shared-connector and signal rules) are owned by each project's repo (its decisions file); this skill is the app mechanics and only points at them.

Key pages: /feature/desktop, /feature/part-libraries, /feature/signals, /feature/pinouts, /feature/local-files/json-format, /files/harness/editing-guide.md (also positioning.md, notes.md linked from it).

## Drawings stay clean

- Only parts the owner asked for, nothing "not used", no added coverings / sleeves / extra splices, no unused part definitions; the owner's saved file wins - change the gate, not their drawing.

## 0. Wire list first (required before building a harness)
Do not draw or generate a `.harness` file until the project has a wire list in a spreadsheet (Excel, Google Sheets or CSV). With a complete wire list, the MCP/JSON tools (or the app's Excel import, https://docs.harness.design/guides/excel-import) can build the harness almost directly; without one, stop and make or ask for it first.
- **Wires sheet**, one row per physical wire segment, columns in this order (grouped: the wire, then its From end, then its To end):
  1. Wire ID (unique: W1, W2, ...)
  2. Signal (short name, e.g. `CAN H`, `12V SW`; becomes the harness.design signal)
  3. Description (optional, plain words)
  4. Signal group
  5. Twist/Shield group (e.g. TP1 twisted pair, SH1 shield; blank if none)
  6. Color (base/stripe, e.g. `YE/BK`; explain any custom codes on a Key sheet)
  7. AWG
  8. Wire part number
  9. Length (mm; TBD allowed)
  10. From device (optional)
  11. From connector (or splice SPn)
  12. From pin/cavity
  13. From terminal part number (optional; the app can pick contacts from the connector part number)
  14. From seal part number (optional; must fit the wire's outside diameter)
  15. From strip length (optional)
  16. From label (wire label at this end)
  17. To device (optional)
  18. To connector (or splice SPn)
  19. To pin/cavity
  20. To terminal part number (optional)
  21. To seal part number (optional)
  22. To strip length (optional)
  23. To label (wire label at this end)
  24. Net (optional, reference only; harness.design works out nets itself through splices and mated connectors)
  25. Notes (always last)
- Splices are named nodes (SP1, SP2, ...) in the From/To columns: one row per wire into or out of the splice, never one row for a whole spliced run.
- Use exactly the same connector name everywhere it appears.
- **Connectors sheet**: connector name, part number, mating part number (so the app assigns real parts).
- Labels are called out per connector end: each end of a wire gets its own label.
- Before the wire list: the circuit list, and the pinouts of every device and connector involved, taken from datasheets or manuals (cite them; mark unknowns TBD, never guess).
- A circuit list is one row per circuit (a circuit is one job, like "fuel pump power" or "coolant temp sensor"): what it powers or senses, its power source and fuse/relay, what switches or controls it, its ground, the devices and connectors it touches, and its current draw or load. Each circuit becomes one or more wires in the wire list.
- Alongside it: the parts list for connectors, contacts, seals and plugs, using parts the owner already has where they meet spec.
- Order: circuit list, pinouts, wire list, parts, then build the harness from the wire list, then the layout, then open in the app as the final check.
- Routing (the physical path through the vehicle or machine and the bundle lengths) is optional: ask for it, but do not block on it. If none is given, lay the harness out cleanest left to right in from-to order (sources on the left, loads on the right), with a straight trunk and branches, and mark the lengths TBD.
- The wire list is the source of truth: if the drawing and the list disagree, fix the list first, then the drawing. Keep one wire list per project, in the project repo.

## 1. Desktop live-file workflow (default)
- The desktop app opens local `.harness` files (File > Open, or double-click), saves to the file immediately, and watches it: saved external changes reload at once. Files are pretty-printed JSON (2-space indent, stable key order), so they diff in git.
- The owner edits in the app, then commit. Cloud upload is optional (sharing only).
- **Conflict rule: the version saved to disk wins.** If the app has unsaved edits when an agent saves, the app's edits are discarded. So agents pause while the owner is editing, and ask before writing a file they may have open.
- **Format version: files follow the app's current schema (v1.2 since 2026-10-15).** The app migrates an older file on open and re-saves it, so an old file in git shows up as a rewrite the first time anyone opens it. When the app moves to a new schema, migrate every file in the repo once, exactly as the app does (compare with an app re-save of one file), prove it lossless, and update the readers; never hand-write an old version. Current format: https://docs.harness.design/files/harness/editing-guide.md and /files/harness/schema/v1.2.json.
- Write files atomically (temp file, then rename) so the app never reads a half-written file. Keep the app's formatting (2-space indent, key order); do not reformat files wholesale. Never change `version`; `$schema`/`$docs` are rewritten by the app; `formboardData` is ignored on open.
- The app silently deletes content that violates its rules when it opens a file, with no warning. Opening the file in the app is the full validation; the schema only checks structure.
- Moving between modes: Export > Local File (cloud to disk), Upload to cloud... (disk to cloud).

## 2. Cloud upload via MCP (only when asked, for sharing)
- Create with `create_harness`, fill with `set_document_json` (whole document in one call), check with `validate_harness`; `edit_document` / `get_document_json` read and patch.
- Title each upload `<name> YYYY-MM-DD`. Never overwrite an older cloud doc unless the owner asks; create a new one.
- Minified JSON is fine for the wire. Do not keep minified copies in git (they go stale when the file is edited in the app).

## 3. Part libraries (`.harnesslib`)
- A library file holds only `*Parts` arrays, `currency`, `"version": 1.2`, `"kind": "library"`.
- Part configurations (connector, terminal, splice, diode, resistor parts) are an ordered `accessories` list of `{id, type, partId, rule?}` (v1.2). Housing accessories (lock, boot, backshell, mount, dust cover, covering) count once per component; contacts, cavity plugs and seals are per-cavity defaults, first matching `rule` wins. Per-cavity `contactPartId` / `cavityPlugPartId` are overrides. v0.9 held single `lockPartId` / `contactPartId` / ... fields instead (https://docs.harness.design/files/harness/part-library.md).
- Link once: Preferences > Part Libraries > Link existing... Keep the `.harnesslib` in version control next to the `.harness` files it serves; it travels with them (same PR). Library changes pulled from git are picked up while the app is open.
- Parts with the same part number in a harness and a library are the same part. A part needs a part number before it can go in a library. A duplicate part number in a harness gives a warning.
- Sync is per library and per part (all properties equal = in sync); push the harness part to the library or pull the library part into the harness. When they differ, the library wins unless the owner says otherwise.
- Ids: components and parts share one id space per document; existing ids never change.

## 4. Signals / nets
- A signal typed on a cavity or terminal propagates to every empty cavity/terminal on the same net (fills empty ones only). `"propagate": false` stops it. "Make signal global" joins same-named signals on different nets.
- Set an explicit signal where it originates, and an explicit signal with `propagate: false` wherever the name changes (across a device, plug, inline connector or break), so auto-fill never puts the wrong label on the far side. One propagating signal per net. Terminals, flying leads and endpoints do not propagate.
- A net with several signals shows all of them on empty cavities, which is usually a bug.

## 5. Views
- **Schematic** is whatever reads best, often center-out (main connector or module in the middle or top, breakouts around). No overlapping nodes or notes, few crossovers, related circuits grouped, notes to the side, positions on the grid.
- **Layout** reads left to right along the physical route: straight trunk, branches off it, no branch doubling back, a length on each bundle segment. Never join separate harnesses in one layout.
- Connectors, terminals, splices, diodes and resistors need `schematicPosition` and/or `layoutPosition`; never set a position on a group (derived from members). Notes need `schematicPosition`.
- **Shared connectors are drawn whole** (all projects): the WHOLE connector in every file; cavities another file owns get `"notConnected": true` (no signal, no contact, `"cavityPlugPartId": null` so only the owner counts it) plus a note "see <other file>" (https://docs.harness.design/component/connector "not-connected cavities"). N/C cavities are not conductors, so they do not count toward the Free-plan connection limit (https://docs.harness.design/plan).
- Devices (ECUs, sensors, switches) are not components: model them as harness-side connectors in a group named for the device.
- Deleting a component: also remove wires, mates, bundles and any `partId`/`contactPartId`/`coveringIds` pointing at it. In group documents references use `<groupId>-<localId>`.

## 6. Known quirks
- Unknown keys are rejected (e.g. `physicalPartGroup`, `shield`). Keep repo-only data outside the harness file.
- Free plan: 100 connections per harness, also for local files.
- The per-wire splice gauge warning is a false alarm.
- Node sizes/heights are not documented, so overlap checks are estimates; look at the drawing in the app.
- Do not hand-write what the app regenerates; rely on opening the file as the final check.
