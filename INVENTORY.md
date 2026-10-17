# Inventory (generated from workstation.lock.yaml - do not edit)

## Repos (cloned at a pinned commit, never copied)

| Repo | URL | Ref | Commit | Setup |
|---|---|---|---|---|
| handbuilt-cad | https://github.com/living-relation/handbuilt-cad.git | main | 9d7ca5965919cb607512543d6bf6412c6f5d8f64 | setup.sh |

## Upstream tools (pinned)

| Tool | Version / pins |
|---|---|
| freecad | 1.1.4 |
| uv | 0.13.0 |
| gitleaks | 8.30.1 |
| python_wsl | 3.13.16 |
| pip_info | build123d 0.13.0, cadquery-ocp-novtk 8.0.1.1.0, trimesh 5.1.1, numpy 2.5.3, open3d 0.20.0, pyvista 0.49.0 |
| apt | calculix-ccx 2.21-1build1, gmsh 4.14.0+ds1-1build4, paraview 6.0.1+dfsg1-7, occt-misc 7.9.2+dfsg-4 |
| openfoam | 14 |
| elmer | source TBD, sha256 TBD, optional True |
| fusion360 | manual True |

## Outside dependencies (listed only; not installed or copied)

| Item | Where | Version | How to enable |
|---|---|---|---|
| harness-design-mcp | https://app.harness.design/mcp | - | Add the URL as an MCP server in Claude/Cursor, then sign in by hand. |
| fusion-mcp-addin | http://127.0.0.1:27182/mcp | TBD | Install Fusion 360, enable Autodesk's MCP add-in (Utilities > Add-ins), optionally add the URL to Claude/Cursor. |
| blender-mcp-addon | TBD | TBD | Install the upstream Blender MCP add-on in Blender (Edit > Preferences > Add-ons). |
| windows-mcp | windows-mcp | 0.8.8 |  |

## Skills sources

- repos.handbuilt-cad: `skills/`
- self: `skills/`

Models folder: `{desktop}/models` (created by setup if missing, add-only).

CAD models included: none. Patches: 0.

## Open items

- Fusion MCP Claude Desktop extension version
- Blender MCP add-on source and version
- windows-mcp installed version
- Elmer source
