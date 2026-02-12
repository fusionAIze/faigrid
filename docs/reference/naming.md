# Naming conventions

## Hosts
- `nexus-edge`  = edge node (secure ingress + DNS)
- `nexus-core`  = core node (automation/apps)
- `nexus-worker` = compute/runners
- `nexus-backup` = backup storage/target

## Users
- `nexus`      = admin/bootstrap user (sudo)
- `nexus-ops`  = daily operator user (sudo, not docker)

Guidelines:
- Prefer SSH key auth only.
- Keep `AllowUsers` restricted to known accounts.
- Use separate SSH keys per role (admin vs ops vs backup).
