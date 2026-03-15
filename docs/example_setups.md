# Infrastructure Examples — fusionAIze Nexus Labs

The **4+1 Node Architecture** of Nexus Labs intentionally decouples the *functional role* of a node from its *physical hardware*. 

This allows the ecosystem to scale from a low-cost DIY homelab to a multi-region enterprise cloud deployment without changing the core scripts.

Below are two concrete examples of how this architecture can be deployed in the real world.

---

## Example A: The "Local Agency Lab"
*This is the default reference setup: cost-effective, secure, and physically isolated from the cloud.*

This setup is ideal for small teams, autonomous agent developers, or local agencies that want to experiment with AI tooling and orchestration without paying monthly cloud execution fees or trusting third-party APIs with sensitive data.

### Node Mapping
1. **nexus-edge**: A **Raspberry Pi 4**.
   - Placed in the DMZ or exposed via a single router port-forward.
   - Runs `Pi-hole` for local ad-blocking and `Caddy` for TLS termination and reverse proxying back into the core.
2. **nexus-core**: A powerful **Mini-PC** (e.g., Intel NUC, 32GB RAM).
   - Hidden safely in the local network. 
   - Runs the heavy lifting: `n8n` orchestration, PostgreSQL databases, `OpenClaw` agent service, and the Workbench tooling.
3. **nexus-worker**: An **older MacBook Pro** (e.g., M1 Max with unified memory).
   - Also hidden in the local network. 
   - Runs `LM Studio` or `Ollama` exposing a local API server. It utilizes Apple Silicon to serve LLMs efficiently for code review or summarization tasks triggered by the Core.
4. **nexus-backup**: A **Synology NAS**.
   - Accepts daily encrypted rsync/Restic snapshots from the Core's database and state volumes.
5. **nexus-external**: A **Hetzner Cloud VPS**.
   - Hosted publicly. Runs the Project Management GUI (e.g., Plane) or a lightweight external `n8n` to catch internet-facing webhooks and queue them for the internal edge.

---

## Example B: The "Full Cloud Deployment"
*This setup is designed for scalable, high-availability SaaS products built on top of the Nexus architecture.*

All nodes are virtualized and deployed across data centers. This maximizes uptime and bandwidth but incurs monthly cloud costs.

### Node Mapping
1. **nexus-edge**: A massive **Cloudflare Tunnel / AWS API Gateway** or a dedicated **Nginx VPS**.
   - Handles DDoS protection, global TLS routing, and SSO (Authelia/Authentik) blocking malicious traffic at the perimeter.
2. **nexus-core**: A dedicated **Hetzner / AWS EC2 Compute Server** (e.g., 64GB RAM, NVMe).
   - Tightly firewalled, only accepting traffic from the Edge VPN.
   - Runs the central `n8n` automation clusters, `Redis` queues, and the heavily trafficked `OpenClaw` agent dispatchers.
3. **nexus-worker**: Auto-scaling **RunPod / AWS p4d GPU Instances**.
   - Deployed dynamically only when large-scale parallel LLM inference is requested by the Core orchestrator.
4. **nexus-backup**: An **AWS S3 Bucket** or **Backblaze B2**.
   - Object-locked, immutable storage receiving hourly encrypted configuration blobs and database dumps.
5. **nexus-external**: (Merged into the public-facing Edge layer in this cloud-native paradigm).

---

> Remember: The central `install.sh` orchestrator script treats both examples identically. It connects via SSH to the target IP, reads the topology, and executes the role payload regardless of whether the target is a Raspi under a desk or an AWS EC2 instance.
