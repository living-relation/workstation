<!-- app-locks:v1 -->
## App locks (one agent at a time on this PC)
Fusion work uses Autodesk's official Fusion MCP servers (exact links and config line coming later).
The harness.design desktop app (section 5b) has one lock on this PC. Any session in any repo is blocked while another holder has that lock. `-Repo` is recorded and shown only. It does not limit who is blocked. The rules are in `{{PROJECTS_ROOT}}\active\workstation\agents\projects-AGENTS.md`. Acquire before use, check in at least every 10 min, and release when done. Never delete the lock file by hand. harness.design MCP cloud tools do not need the lock. An agent delete goes through the desktop app under the lock.
- Acquire: `powershell -NoProfile -ExecutionPolicy Bypass -File "{{PROJECTS_ROOT}}\active\workstation\workstation\fusion-lock\fusion-lock.ps1" acquire -Name harness-design -Holder <your name> -Kind claude-code|cursor|remote -Repo <repo path> -Files rBjB,QjYZ`
- Check in: `powershell -NoProfile -ExecutionPolicy Bypass -File "{{PROJECTS_ROOT}}\active\workstation\workstation\fusion-lock\fusion-lock.ps1" checkin -Name harness-design -Holder <your name>`
- Release: `powershell -NoProfile -ExecutionPolicy Bypass -File "{{PROJECTS_ROOT}}\active\workstation\workstation\fusion-lock\fusion-lock.ps1" release -Name harness-design -Holder <your name>`
<!-- /app-locks:v1 -->
