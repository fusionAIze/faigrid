# Remote Worker Tunneling (Agentic Grid)

In a distributed Agentic Grid, your **Worker Nodes** (e.g., an older MacBook Pro running LM Studio) often sit in different physical networks (like your home LAN) than your **Core Node** (e.g., a Hetzner VPS).

Exposing local LLM endpoints publicly to the internet is dangerous. Instead, we use outbound reverse tunneling. The Worker dials *out* to the Core.

## Method 1: SSH Reverse Tunnels

If you have SSH access to your `nexus-core` server, you can map your local `LM Studio` port (default `1234`) backwards to a port on the Core server.

### On your Worker (MacBook):
```bash
# This binds the Core's remote port 1234 to your local port 1234.
ssh -N -R 127.0.0.1:1234:127.0.0.1:1234 user@nexus-core.example.com
```
*Tip: Use `autossh` in a background daemon to keep this tunnel persistently alive across network drops.*

### On your Core (n8n/OpenClaw):
You can now instruct AI agents to route API calls to `http://127.0.0.1:1234/v1`. The traffic securely routes back through the SSH tunnel to your MacBook.

---

## Method 2: Tailscale / WireGuard Mesh

For true production deployments involving multiple Workers, a VPN mesh is superior.

1. Install Tailscale on the **Core Node**.
2. Install Tailscale on your **Worker Node(s)**.
3. Configure `LM Studio` to bind to the Tailscale IP (`100.x.x.x`) rather than `localhost:1234`.
4. In `n8n` or `OpenClaw`, address the worker targets via their static Tailscale IPs.

> This completely bypasses the need for the `nexus-edge` reverse proxy for inter-node model serving, saving bandwidth and latency.
