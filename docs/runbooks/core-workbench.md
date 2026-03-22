# Core Workbench Control Center

The `grid-core` instance introduces an extensible **Workbench Control Center**, serving as a terminal-based UI and plugin registry for managing the various CLI tools, routing agents, and memory stores.

## Architectural Goal
Instead of manually hunting down `npm install`, `pipx upgrade`, or `git pull` commands for different tools, the Control Center unifies them. It scans the `plugins/` registry, groups them by categories (CLIs, Routers, Agents, Memory), and offers a single interface.

## Launching the Control Center

Execute the main script via SSH on your `grid-core` instance:

```bash
bash core/workbench/scripts/control-center.sh
```

### CLI Arguments
You can bypass the interactive menu by passing arguments:
- `bash control-center.sh status` -> Prints the table of all tools.
- `bash control-center.sh update-all` -> Loops through all installed tools and runs their updater sequences.

## Plugin Structure

Plugins are grouped into isolated folders within `core/workbench/scripts/plugins/`. Adding a new tool (e.g., a new local model orchestrator) is as simple as defining a new `.sh` file inside the appropriate category folder.

A plugin file must define metadata and three lifecycle functions:
- `TOOL_NAME`
- `TOOL_CATEGORY` (clis / routers / memory / agents / automation / wrappers)
- `TOOL_DESC`
- `tool_install()`, `tool_update()`, `tool_status()`

See `plugins/_template.sh` for an example.
