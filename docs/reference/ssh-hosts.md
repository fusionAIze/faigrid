# SSH hosts (client-side)

This document maps the fusionAIze Grid host aliases to roles and default users.

## Current (Step 01 + Step 02)
- `grid-edge`      -> edge node (DNS / Pi-hole / ingress), user: `nexus`
- `grid-core`      -> core node (automation/apps), user: `nexus`
- `grid-core-ops`  -> core node (daily ops), user: `nexus-ops`

## Why separate users?
- `nexus` is the bootstrap/admin user (sudo, setup work)
- `nexus-ops` is a daily operator user (sudo, but not docker)

## Where to put it
- macOS/Linux client: `~/.ssh/config`

Use the example:
- `core/base/client/ssh/config.snippet.example`
