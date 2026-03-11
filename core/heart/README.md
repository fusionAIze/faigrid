# Core Heart

Canonical stack files live in this module:

- `compose/docker-compose.yml` for the container stack
- `compose/.env.example` as the base env template
- `scripts/install.sh` to stage the stack on `nexus-core`

The install script copies `compose/.env.example` to `/opt/fusionaize-nexus/core-heart/.env`.
