# fusionAIze Grid: Backup, Recovery, and Observability

A sovereign execution substrate must be recoverable. If an explicitly isolated node fails, Solo Operators or SMBs must be able to restore their **Team Operating Logic** precisely.

## Observability Discipline (Log Rotation)

Grid components write to `/var/log/faigrid/grid-system.log`. To prevent disk exhaustion during large agentic workflows, implement `logrotate`.

1. Copy the template to the system:
```bash
sudo cp docs/templates/grid-system.logrotate /etc/logrotate.d/faigrid
```
2. Validate the rules:
```bash
sudo logrotate -d /etc/logrotate.d/faigrid
```

## Automated Snapshots (Systemd Timers)

Grid ships with a hardened `backup.sh` script that snapshots:
- `~/.grid-state` (Topology)
- `~/.config/faigrid` (Runtime API Secrets)
- Postgres Database (n8n orchestration state)
- Docker Volumes

It is designed to run automatically.

### Setting up the automated Cron/Timer
For a Solo Operator, a simple root cron job is sufficient:
```bash
sudo crontab -e
```
Add the nightly execution pattern:
```text
0 3 * * * /bin/bash /opt/faigrid/core/heart/scripts/backup.sh >> /var/log/faigrid/backup.log 2>&1
```

## The Recovery Pipeline

If your hardware fails, or you are migrating to a larger Cloud Server Profile (Small Team / SMB):

### 1. Re-install Grid Baseline
```bash
git clone https://github.com/typelicious/faigrid.git faigrid
cd faigrid && bash install.sh
```

### 2. Restore State and Secrets
Extract your backed-up tarballs into `~/.grid-state` and `~/.config/faigrid/`.

### 3. Restore Volumes
```bash
docker run --rm \
  -v grid_core_n8n_data:/data \
  -v /var/backups/faigrid:/backup \
  alpine:3.20 sh -lc "cd /data && tar -xzf /backup/n8n_data_YYYY-MM-DD_HHMM.tar.gz ."
```

### 4. Restore Database
```bash
docker cp /var/backups/faigrid/postgres_YYYY-MM-DD_HHMM.sql grid-postgres:/tmp/
docker exec -it grid-postgres psql -U n8n -d n8n -f /tmp/postgres_YYYY-MM-DD_HHMM.sql
```

Bring the `grid-core` stack down and back up:
```bash
docker compose -f core/heart/compose/docker-compose.yml restart
```
