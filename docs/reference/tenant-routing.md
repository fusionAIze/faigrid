# Tenant routing and cost attribution

`core/tenant/routing.sh` implements FND-003: a request that names a tenant is
routed to the upstream inference endpoint and recorded against that tenant, with
the cost computed from the tokens the upstream itself reported. A request that
names no tenant is **refused** rather than attributed to nobody.

The library sources no other file and defines no globals; source it and call its
functions.

```bash
source core/tenant/routing.sh
```

## Inputs

| Variable                     | Meaning                                                        | Default                     |
| ---------------------------- | -------------------------------------------------------------- | --------------------------- |
| `FAIGRID_ORG_ID`             | Organisation the request belongs to (e.g. `veeona-hq`)          | empty                       |
| `X_TENANT_ID`                | Tenant id as a request-level carrier, used when no tenant is passed positionally | empty |
| `FAIGRID_DEFAULT_TENANT`     | Explicit default tenant for untagged requests. Unset means **refuse** | unset                 |
| `FAIGRID_UPSTREAM`           | Upstream `host:port`                                            | `127.0.0.1:8080`            |
| `FAIGRID_ROUTE_TIMEOUT`      | Per-request transport timeout, seconds                          | `20`                        |
| `FAIGRID_PRICE_IN_PER_1K_MC` | Input price, milli-US-cents per 1k tokens                       | `1000` (1.000 USD / 1k)     |
| `FAIGRID_PRICE_OUT_PER_1K_MC`| Output price, milli-US-cents per 1k tokens                      | `2000` (2.000 USD / 1k)     |
| `FAIGRID_ROUTING_LOG`        | Append-only JSONL record file                                   | `${HOME}/.config/faigrid/routing.jsonl` |
| `FAIGRID_ROUTE_STUB`         | `1` stubs the transport (tests only; never a real round-trip)   | unset                       |

## Routing a request

```bash
tenant_route_request [tenant-id] [prompt-tokens] [completion-tokens] [upstream]
```

- If `tenant-id` is omitted or empty, `X_TENANT_ID` is used.
- The upstream response body is printed on stdout.
- The call is recorded on success.

Exit codes:

| Code | Meaning                                                                    |
| ---- | -------------------------------------------------------------------------- |
| `0`  | Routed and recorded                                                        |
| `8`  | **Refused**: no tenant id and no explicit default — the safe outcome       |
| `9`  | Transport or upstream failure before a record could be made                |

## Cost

The cost is `prompt_tokens * price_in + completion_tokens * price_out`, where
both token counts come from the upstream's response, never from a fixture. It is
recorded as `cost_usd` with three decimals. The price is an input; the tokens are
the measurement.

## The defect this prevents: silent attribution to nobody

An empty-string tenant that passes a "not null" check is the defect. Every
comparison in this file is on the **value**:

- `tenant_route_request ""` with no `FAIGRID_DEFAULT_TENANT` exits `8` and writes
  no record.
- Setting `FAIGRID_DEFAULT_TENANT` is an explicit operator choice; the default is
  then recorded **literally** as that name, so an untagged request is never
  indistinguishable from a tagged one.
- `tenant_records_are_attributed` returns non-zero (printing the offending line)
  if any record's `tenant` is empty or absent. It is the post-condition check the
  journal can be audited with.

## Record format

One JSON object per line, appended atomically (the file is rebuilt from its
current contents plus the new line, then swapped, so a concurrent reader never
sees a torn record):

```json
{"ts":"2026-09-23T16:20:39Z","component":"tenant-router","severity":"INFO","org_id":"veeona-hq","tenant":"veeona-hq","model":"unknown","cost_usd":2.000,"prompt_tokens":1000,"completion_tokens":500}
```

The `ts`/`component`/`severity` fields follow `docs/reference/event-schema.md`;
this file is a distinct write profile and does not route through `log_event()`.

## Messaging surface

The tenant also round-trips a real transport:

```bash
tenant_messaging_send  <tenant-id> <message> [upstream]
tenant_messaging_check <tenant-id> <message> [upstream]
```

`tenant_messaging_send` refuses an empty tenant id (exit `8`) and otherwise sets
`X-Tenant-ID` on the request. `tenant_messaging_check` prints
`sent <tenant>|received <tenant>` only when the upstream acknowledges the same
tenant.

## Proof

`tests/unit/07-tenant-routing.bats` covers all three criteria. Criterion 2 is
proven by a real request: two Docker containers on one bridge, the routing path
run inside the client container against a live token-counting upstream. If Docker
is unavailable the test skips and criterion 2 is **INCONCLUSIVE**, never passed.
