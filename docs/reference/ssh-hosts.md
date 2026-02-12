# SSH hosts (client-side)

This document maps the Nexus Labs host aliases to roles and default users.

## Current (Step 01 + Step 02)
- `nexus-edge`      -> edge node (DNS / Pi-hole / ingress), user: `nexus`
- `nexus-core`      -> core node (automation/apps), user: `nexus`
- `nexus-core-ops`  -> core node (daily ops), user: `nexus-ops`

## Why separate users?
- `nexus` is the bootstrap/admin user (sudo, setup work)
- `nexus-ops` is a daily operator user (sudo, but not docker)

## Where to put it
- macOS/Linux client: `~/.ssh/config`

Use the example:
- `core/base/client/ssh/config.snippet.example`
