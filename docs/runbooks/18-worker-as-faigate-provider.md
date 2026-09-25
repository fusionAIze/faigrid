# Step 18 — The worker is a faigate provider (GO-009)

Scope: make the grid-worker reachable as a faigate provider so that a completion
request from the workstation routes through faigate to the local qwen model on
the worker. This is a **feature** that also establishes the failure mode this
round exists to prevent: a sleeping worker must NOT look like success because
faigate quietly routes elsewhere.

This is lane **GO-009** of sequence `veeona-golive`, phase 3.

## 1. Worker reachability

The grid-worker is a MacBook Air M2 (Mac14,7, 8 GB) at 192.168.178.30 running
llama.cpp's server at 0.0.0.0:8080. D7 as amended (2026-09-24) binds the LAN
directly behind an api-key:

- **Engine:** llama-server at `/opt/homebrew/bin/llama-server`
- **Model:** `Josiefied-Qwen2.5-Coder-7B-Instruct-abliterated-v1.Q4_K_M.gguf`
- **Config:** `-c 8192 --parallel 1 -fa on -ctk q8_0 -ctv q8_0 -ngl 99 --host 0.0.0.0 --port 8080`
- **Auth:** `Authorization: Bearer <LLAMA_API_KEY>` — the key is read from
  `~/.config/envctl/faigrid.env` (mode 600) and passed as an environment
  variable, never as `--api-key` (argv is world-readable via ps on macOS)
- **Service durability:** LaunchAgent `com.fusionaize.grid-worker` (KeepAlive,
  restarts on crash after 10s throttle)

The provider address `http://192.168.178.30:8080/v1` is the same for both
faigate instances — the native process on the workstation and the container on
grid-core — because a container on `faigrid_inference_net` routes to the LAN
(measured: default via 172.20.0.1).

## 2. The faigate provider block

The provider block is workstation-local and is NOT committed to any repository.
Recorded here for reference (measured 2026-09-25):

```yaml
grid-worker-qwen:
  api_key: ${LLAMA_API_KEY}
  backend: openai-compat
  base_url: ${GRID_WORKER_BASE_URL:-http://192.168.178.30:8080/v1}
  capabilities:
    cost_tier: free
    latency_tier: slow
  lane:
    benchmark_cluster: local-inference
    canonical_model: local/qwen2.5-coder-7b
    cluster: local-inference
    context_strength: low
    degrade_to:
    - deepseek/v4-flash
    family: grid-worker
    freshness_hint: measured on the worker 2026-09-24, not estimated
    freshness_status: fresh
    last_reviewed: '2026-09-24'
    name: local-worker
    quality_tier: free
    reasoning_strength: low
    review_age_days: 0
    route_type: direct
    same_model_group: local/qwen2.5-coder-7b
    tool_strength: low
  max_tokens: 2048
  model: qwen2.5-coder-7b-instruct
  tier: fallback
  timeout:
    connect_s: 5
    read_s: 300
```

The provider is addressable ONLY as `grid-worker-qwen`. The model names
`qwen2.5-coder-7b-instruct` and `local/qwen2.5-coder-7b` both return
'Model not found'.

### 2.1 Identification discriminator

The response `model` field carries the full gguf path
(`.../Josiefied-Qwen2.5-Coder-7B-Instruct-abliterated-v1.Q4_K_M.gguf`). The
model describes ITSELF in prose as 'GPT-4' — a training artifact of this
abliterated Qwen. **Never use the prose content as identification.** The
discriminator is:

1. **model field** must contain the gguf path (not `deepseek-flash`)
2. **reasoning_tokens** must be absent or None (llama.cpp does not populate it;
   deepseek does)

### 2.2 Known limitation: silent fallback

When the worker is unreachable (asleep, network down, server stopped), faigate
silently falls back to `deepseek/v4-flash` (the `degrade_to` target). The HTTP
response returns 200 with a cloud model and NO indication that the original
provider was unavailable. Evidence measured 2026-09-25:

```
Response headers:
  x-faigate-provider: deepseek-v4-flash
  x-faigate-circuit: CLOSED
  x-faigate-layer: direct

Response body:
  model: deepseek-flash
  _faigate.provider: deepseek-v4-flash
  completion_tokens_details.reasoning_tokens: 5
```

The faigate server logs DO record the failure:
```
WARNING Provider grid-worker-qwen marked unhealthy after 3 failures: ...
WARNING Provider grid-worker-qwen failed: ..., trying next...
```

But no signal reaches the client. To verify the worker is actually answering
rather than faigate silently routing elsewhere, check:
- The `model` field in the response (must be the gguf path, not deepseek-flash)
- The absence of `reasoning_tokens`

This limitation is tracked against faigate's provider health reporting surface.
The global `fallback_chain` in the faigate config causes the silent fallback.
Removing `grid-worker-qwen` from the chain (or making it the last entry) does
not help — the `_validate_health` method iterates the chain for any healthy
provider when the primary is down.

## 3. verify.sh health check

`worker/scripts/verify.sh` gains an HTTP inference endpoint probe (added by
GO-013, verified by GO-009). After checking CLI presence for ollama, lms,
llama.cpp and tailscale, it probes the health URL:

```
echo "[grid-worker] Probing inference endpoint: $(worker_health_url)"
if worker_health_check; then
    echo "[SUCCESS] Inference endpoint is answering."
else
    echo "[FAIL] Inference endpoint did not answer."
    exit 1
fi
```

The health check is configurable via environment variables:
- `WORKER_HEALTH_URL` (default: `http://127.0.0.1:${WORKER_PORT:-8080}/v1/models`)
- `WORKER_HEALTH_TIMEOUT` (default: 5 seconds)

When the endpoint does not answer, verify.sh exits 1 with the URL named in the
error message. The test at `tests/unit/11-worker-env.bats` proves this by
setting `WORKER_HEALTH_URL` to `http://127.0.0.1:1/v1/models` and asserting
non-zero exit with the URL in the output.

## 4. Verification procedure

### 4.1 Local model identification

```bash
curl -s -X POST http://127.0.0.1:8090/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"grid-worker-qwen","messages":[{"role":"user","content":"test"}],"max_tokens":10}'
```

The response `model` field must contain the gguf path. `reasoning_tokens` must
be absent. A response with `model: deepseek-flash` and `reasoning_tokens` set
means the request was silently routed to a cloud provider.

### 4.2 Provider unavailable detection

Stop the worker or block port 8080, then repeat the request. The response will
return 200 with a cloud model — this is the expected failure mode. Check the
faigate server logs for the provider failure warning.

### 4.3 verify.sh health check

```bash
bash worker/scripts/verify.sh
```

With the endpoint answering: exits 0. With the endpoint down: exits 1 and names
the URL.

## 5. Decision history

| ID | Date | Decision | Status |
|----|------|----------|--------|
| D1 | 2026-09-24 | Rejected LAN binding as unauthenticated port | SUPERSEDED by D7 |
| D6 | 2026-09-24 | Made the account a fixed appliance with sshd ForcedCommand | NO LONGER IN FORCE (removed 2026-09-24) |
| D7 | 2026-09-24 | LAN binding behind api-key; no tunnel, no sidecar | **HOLDS** |
| D7a | 2026-09-24 | Amendment: api-key added same day, env var not argv | **HOLDS** |

See `prd.json` in the planning repository for the full operator decisions.
