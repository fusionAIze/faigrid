# IP plan (LAN)

This repo assumes a simple, static LAN IP plan for predictable hostnames and SSH/VNC access.

| Component | Hostname     | Role                         | IPv4 (example) |
|----------:|--------------|------------------------------|----------------|
| Edge      | grid-edge   | DNS / Pi-hole / ingress      | 192.168.178.10 |
| Core      | grid-core   | automation + OpenClaw + apps | 192.168.178.20 |
| Worker    | grid-worker | runners / LLM tools          | 192.168.178.30 |
| Backup    | grid-backup | backup target                | 192.168.178.40 |

Notes:
- Keep DNS (Pi-hole) on the edge node (grid-edge).
- Use DHCP reservations on the router where possible.
- If DHCP client utilities are missing, configure static IPv4 via NetworkManager or systemd-networkd depending on your install.
