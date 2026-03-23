# Naming conventions

## Hosts
- `grid-edge`  = edge node (secure ingress + DNS)
- `grid-core`  = core node (automation/apps)
- `grid-worker` = compute/runners
- `grid-backup` = backup storage/target

## Users
- `grid`      = admin/bootstrap user (sudo)
- `grid-ops`  = daily operator user (sudo, not docker)

Guidelines:
- Prefer SSH key auth only.
- Keep `AllowUsers` restricted to known accounts.
- Use separate SSH keys per role (admin vs ops vs backup).
