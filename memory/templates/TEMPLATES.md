# Templates

install.ps1 fills these placeholders at install time. Nothing here holds memory or machine names.

| Placeholder | Filled with |
|---|---|
| `{{USERPROFILE}}` | the user's profile folder (`$env:USERPROFILE`), backslashes |
| `{{USERPROFILE_FWD}}` | same, forward slashes |
| `{{PROJECTS_ROOT}}` | the Projects root (`-ProjectsRoot`, default `%USERPROFILE%\Projects`), backslashes |
| `{{PROJECTS_ROOT_FWD}}` | same, forward slashes |
| `{{CLAUDE_PROJECT_KEY}}` | Claude Code's folder name for the Projects root: the full path with every character that is not a letter or digit turned into `-` |
| `{{USERNAME}}` | the Windows user name (`$env:USERNAME`) |
| `{{DATE}}` | install date, `yyyy-MM-dd` |
| `{{TOOLKIT_PATH}}` | the full path of the toolkit inside the workstation repo clone (`<clone>\<PackageFolder>`, `PackageFolder` in `toolkit.psd1`); the toolkit runs from there |
| `{{TOOLKIT_PULL}}` / `{{TOOLKIT_STATUS}}` | the toolkit's pull and status scripts (`PullScript` / `StatusScript` in `toolkit.psd1`) |
| `{{PROJECT_SLUG}}` | NOT filled by install.ps1. Filled per project during migration: the `active\` folder name, lowercased, every run of non-letters/digits turned into `-` |

| File | Goes to | How |
|---|---|---|
| `claude-global-memory-section.md` | `~\.claude\CLAUDE.md` | appended if the marker is missing (file created if missing) |
| `working-memory-CLAUDE.md` | `<Projects>\_claude\Claude Projects\Working Memory\CLAUDE.md` | created if missing, else appended if the marker is missing |
| `projects-AGENTS.md` | `<Projects>\AGENTS.md` (the one root guide; there is no root `CLAUDE.md`) | created if missing, else only its marked memory + bridge section is appended if the marker is missing. Skipped (WARN) while a root `CLAUDE.md` that already has the marker still exists: merge it first (REORGANIZE.md step 5) |
| `claude-shared-memory.mdc` | `~\.cursor\rules\claude-shared-memory.mdc` | created if missing, else the body is appended if the marker is missing |
| `MEMORY.md` | `<store>\MEMORY.md` | created only if missing |
| `unassigned-INDEX.md` | `<store>\_unassigned\INDEX.md` | created only if missing |
| `cursor-notes-INDEX.md` | `<Projects>\_claude\Cursor Notes\INDEX.md` | created only if missing |
| `repo-agent-rule.md` | the top of each repo's `AGENTS.md` (or its `CLAUDE.md` when that is the only guide) | pasted by hand during migration, not by install.ps1; adapt the guide / decisions file names per repo. Existing installs are not refreshed: install only appends a marked block when the marker is missing |
| `project-pointer-line.txt` | one line per project: `CLAUDE.local.md` in a git repo (add `CLAUDE.local.md` to `.git\info\exclude`), else `CLAUDE.md` | added during migration, not by install.ps1; only `{{PROJECT_SLUG}}` is filled |

The project pointer line uses `%USERPROFILE%\.claude\working-memory\<slug>\INDEX.md`, written literally (not a
placeholder). `~\.claude\working-memory` is a junction to the memory store that install.ps1 creates (and the guard hook
recreates if it goes missing), so the same line works on every PC whatever the user name or Projects location.

The Claude instruction texts (account Instructions for Claude and Cowork Global instructions) are not templates: they are
in the package's `instructions\` folder, have no placeholders, and are pasted by hand once per account (MIGRATION.md
step f). Cowork's text uses the same `%USERPROFILE%\.claude\working-memory` path, so it must never hold
`{{PROJECTS_ROOT}}`, `{{USERPROFILE}}` or `{{USERNAME}}`.

Toolkit files have no placeholders and are not copied: they run straight from the package folder named
`PackageFolder` in `toolkit.psd1` inside the workstation repo clone. install.ps1 writes
`%LOCALAPPDATA%\<StateFolder>\<ConfigFile>` (the Projects root) for them; their runtime files go there too.
`toolkit.psd1` is the one place that names the toolkit folder, its scripts and its shortcuts; install.ps1,
install-admin.ps1, uninstall.ps1 and preflight.ps1 all read it.

Marker: `<!-- shared-memory:v1 -->` ... `<!-- /shared-memory:v1 -->`. install.ps1 records in the manifest each section it creates or appends; uninstall.ps1 removes the text between the
markers only for those. A marked section that was already there (or marked by hand) is never removed.
