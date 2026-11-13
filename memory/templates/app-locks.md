<!-- app-locks:v1 -->
## App locks (one agent at a time on this PC)
Fusion (section 5) and the harness.design desktop app (section 5b) each have one lock on this PC. The rules are in `{{PROJECTS_ROOT}}\active\workstation\agents\projects-AGENTS.md`. Acquire before use, check in at least every 10 min, and release when done. Never delete the lock file by hand. harness.design MCP cloud tools do not need the lock. An agent delete goes through the desktop app under the lock.
- Acquire: `powershell -NoProfile -ExecutionPolicy Bypass -File "{{PROJECTS_ROOT}}\active\workstation\workstation\fusion-lock\fusion-lock.ps1" acquire -Name harness-design -Holder <your name> -Kind claude-code|cursor|remote -Files rBjB,QjYZ`
- Check in: `powershell -NoProfile -ExecutionPolicy Bypass -File "{{PROJECTS_ROOT}}\active\workstation\workstation\fusion-lock\fusion-lock.ps1" checkin -Name harness-design -Holder <your name>`
- Release: `powershell -NoProfile -ExecutionPolicy Bypass -File "{{PROJECTS_ROOT}}\active\workstation\workstation\fusion-lock\fusion-lock.ps1" release -Name harness-design -Holder <your name>`
<!-- /app-locks:v1 -->
