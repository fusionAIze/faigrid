# UFW rules reference

The baseline script keeps `grid-core` private by default:

- allow `22/tcp` from the LAN CIDR only
- deny all other inbound traffic
- allow all outbound traffic

VNC stays localhost-only and is expected to be reached through SSH tunnels.
