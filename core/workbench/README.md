# Core Workbench

This module houses the **Terminal Control Center** and **Plugin Registry** for the `grid-core` AI environment. 

It provides a single unified interface to discover, install, update, and manage the various CLI toolkits, memory stores, routing layers, and agents running on your core instance.

## Usage

Run the control center directly from your shell:

```bash
bash core/workbench/scripts/control-center.sh
```

## Adding new plugins

To add a new tool to the registry, simply create a `.sh` file in the appropriate category folder under `core/workbench/scripts/plugins/`. Reference the `_template.sh` file for the expected plugin functions (`tool_install`, `tool_status`, `tool_update`).
