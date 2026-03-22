# UFW reference (grid-edge)

These rules are a **reference baseline** for the `grid-edge` role:
- deny incoming by default
- allow SSH/DNS/HTTP(S) from LAN only
- support IPv4 + IPv6 (ULA /64) for Pi-hole

Adjust to your LAN:
- IPv4 LAN CIDR (example): `192.168.178.0/24`
- IPv6 ULA prefix (example): `fdaf:a57b:d3e6:0::/64`

## Ports
- 22/tcp: SSH (LAN only)
- 53/tcp+udp: DNS (LAN only)
- 80/tcp: Pi-hole admin (LAN only)
- 443/tcp: Pi-hole HTTPS admin (LAN only) / later reverse proxy

