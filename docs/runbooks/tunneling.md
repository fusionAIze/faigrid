# Remote Worker Tunneling (Agentic Grid)

In a distributed Agentic Grid, your **Worker Nodes** (e.g., an older MacBook Pro running LM Studio) often sit in different physical networks (like your home LAN) than your **Core Node** (e.g., a Hetzner VPS).

Exposing local LLM endpoints publicly to the internet is dangerous. Instead, we use outbound reverse tunneling. The Worker dials *out* to the Core.

## Method 1: SSH Reverse Tunnels

If you have SSH access to your `grid-core` server, you can map your local `LM Studio` port (default `1234`) or `Ollama` port (default `11434`) backwards to a port on the Core server.

### On your Worker (MacBook):
```bash
# For LM Studio (port 1234)
ssh -N -R 127.0.0.1:1234:127.0.0.1:1234 user@grid-core.example.com

# For Ollama (port 11434)
ssh -N -R 127.0.0.1:11434:127.0.0.1:11434 user@grid-core.example.com
```
*Tip: Use `autossh` in a background daemon to keep this tunnel persistently alive across network drops.*

### On your Core (n8n/OpenClaw):
You can now instruct AI agents to route API calls to local loopback addresses. 
- **LM Studio**: `http://127.0.0.1:1234/v1`
- **Ollama**: `http://127.0.0.1:11434/v1`

---

## Method 2: Tailscale / WireGuard Mesh

For true production deployments involving multiple Workers, a VPN mesh is superior.

1. Install Tailscale on the **Core Node**.
2. Install Tailscale on your **Worker Node(s)**.
3. Configure `LM Studio` or `Ollama` to bind to the Tailscale IP (`100.x.x.x`).
   - For LM Studio, this is managed in the **Server** tab.
   - For Ollama, set `OLLAMA_HOST=0.0.0.0`.
4. In `n8n` or `OpenClaw`, address the worker targets via their static Tailscale IPs.

> [!TIP]
> **Qwen 3.5-9B Optimization**: When using LM Studio, prefer **GGUF** formats (Q4_K_M or Q5_K_M) for the best balance between speed and quality on MacBook hardware. 
