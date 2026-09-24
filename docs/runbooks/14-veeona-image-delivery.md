# Step 14 — veeona zone image delivery (GHCR)

Scope: establish **with evidence** whether the seven `ghcr.io/veeona/*:0.1.0`
images declared by veeona's `deploy/zones/docker-compose.zones.yml` exist, and —
only if they do — prove an authenticated per-image `docker pull` on
`nexus-core`. This is lane **GO-003** of sequence `veeona-golive`, phase 0. The
lane pulls images and creates no containers, so it does not touch the daemon's
container-creation surface.

Host: `nexus-core` (192.168.178.20, user `nexus`, key-based SSH, non-interactive).

Result up front: **the seven images do not exist**, and **no build pipeline
exists that could produce them**. The per-image pull proof therefore cannot be
captured, and the "trigger the pipeline once" branch cannot be executed. The
missing prerequisite is named in §8.

## 1. The seven images

All seven services are declared with an `image:` and **no `build:` stanza** —
they are pulls, not builds.

| # | Image (as declared) | Container name | Compose line |
| --- | --- | --- | --- |
| 1 | `ghcr.io/veeona/grid-edge:0.1.0` | `veeona-grid-edge` | `deploy/zones/docker-compose.zones.yml:124` |
| 2 | `ghcr.io/veeona/control-plane:0.1.0` | `veeona-z0-control` | `:143` |
| 3 | `ghcr.io/veeona/research-runner:0.1.0` | `veeona-z1-research` | `:162` |
| 4 | `ghcr.io/veeona/production-runner:0.1.0` | `veeona-z2-production` | `:177` |
| 5 | `ghcr.io/veeona/knowledge-graph:0.1.0` | `veeona-knowledge-graph` | `:201` |
| 6 | `ghcr.io/veeona/publish-runner:0.1.0` | `veeona-z3-publish` | `:216` |
| 7 | `ghcr.io/veeona/quarantine-sandbox:0.1.0` | `veeona-zq-quarantine` | `:231` |

## 2. Why a 401 is not an answer

GHCR answers **`401 UNAUTHORIZED`** to an unauthenticated manifest read for
*both* a package that exists but is private *and* a package that does not exist.
The two are indistinguishable without a credential. An answer derived from the
401 is not evidence and is explicitly disallowed by the acceptance criterion.

The evidence below uses an **authenticated** registry read and, crucially, two
controls that separate the cases GHCR is able to express:

* a **private package the credential may not read** → `403 DENIED`
* a **public package the credential may read** → `200`
* a **repository that does not exist** → `404 MANIFEST_UNKNOWN` / `NAME_UNKNOWN`

Because a real private package returns `403`, a private veeona package could not
masquerade as `404`. The `404` results in §4 are therefore genuine non-existence,
not a privacy mask.

## 3. Method

GHCR implements the OCI distribution spec. The read used here is the same flow
`docker pull` uses:

1. Exchange the GitHub credential for a scoped registry token:
   `GET https://ghcr.io/token?service=ghcr.io&scope=repository:<owner>/<name>:pull`
2. Read the manifest with that bearer token:
   `GET https://ghcr.io/v2/<owner>/<name>/manifests/<tag>`
3. Read the tag list: `GET https://ghcr.io/v2/<owner>/<name>/tags/list`

Credential: the workstation's `gh` token for github.com account `typelicious`,
scopes `gist, read:org, repo`. It **does not carry `read:packages`**; that is a
limitation of package *listing*, not of manifest reads — the control
`fusionaize/faigate` (§3.1) proves the credential exercises the private-package
path and is answered by the registry, so the registry read is meaningful.

### 3.1 Controls and the seven — single capture, 2026-09-24T18:17:45Z

| `repository:tag` | HTTP | OCI error code |
| --- | --- | --- |
| `actions/actions-runner:latest` (public, readable) | 200 | — (manifest/index body) |
| `fusionaize/faigate:latest` (private, credential denied) | **403** | `DENIED` |
| `fusionaize/faisignal:latest` (private, credential denied) | **403** | `DENIED` |
| `actions/does-not-exist-zzz:latest` (absent) | 404 | `MANIFEST_UNKNOWN` |
| `veeona/grid-edge:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona/control-plane:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona/research-runner:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona/production-runner:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona/knowledge-graph:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona/publish-runner:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona/quarantine-sandbox:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona-ai/grid-edge:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona-ai/control-plane:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona-ai/research-runner:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona-ai/production-runner:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona-ai/knowledge-graph:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona-ai/publish-runner:0.1.0` | 404 | `MANIFEST_UNKNOWN` |
| `veeona-ai/quarantine-sandbox:0.1.0` | 404 | `MANIFEST_UNKNOWN` |

Anonymous control, for contrast (this is the signal that is *not* used as an
answer): `https://ghcr.io/v2/veeona/grid-edge/manifests/0.1.0` → `401
UNAUTHORIZED`. The tag-list read for the same repository is `404 NAME_UNKNOWN`
("repository name not known to registry").

## 4. Result: the seven images do not exist

Both namespaces the images could plausibly live in were read with the credential:

* **`ghcr.io/veeona`** — the namespace literally declared by the compose. Every
  one of the seven returned `404 MANIFEST_UNKNOWN`; the tag list returned
  `404 NAME_UNKNOWN`.
* **`ghcr.io/veeona-ai`** — the lowercased form of the only GitHub organisation
  that is actually named veeona (see §5). Every one of the seven returned
  `404 MANIFEST_UNKNOWN`.

Against the controls in §3.1, `404 MANIFEST_UNKNOWN` is the registry's
"repository not known" answer. The seven `0.1.0` tags were never built or never
pushed.

## 5. The declared namespace does not correspond to an existing GitHub account

`ghcr.io/<owner>/...` requires `<owner>` to be a GitHub user account or
organisation. Measured:

* `GET https://api.github.com/users/veeona` → `404`
* `GET https://api.github.com/orgs/veeona` → `404`
* The only veeona GitHub organisation is **`Veeona-AI`** (lowercased
  `veeona-ai`), which the credential is a member of. `veeona-ops`'s repository
  registry maps the canonical `veeona/*` source to the `Veeona-AI/*` mirror.

So the image prefix `ghcr.io/veeona/` in the compose is, at best, mismatched with
the ecosystem's actual GitHub organisation; the correct prefix, if images were
published to the mirror org, would be `ghcr.io/veeona-ai/`. Neither namespace
holds the seven images. Correcting the compose namespace is **not** done here —
the veeona repository is read-only for this lane — and it would not change the
result: the images do not exist under either.

## 6. There is no build pipeline

Criterion 3 assumes a veeona pipeline that builds the seven images. No such
pipeline exists. Measured across the whole local veeona organisation (all
repositories, excluding `.git`, virtualenvs and caches):

* no `Dockerfile` / `*.dockerfile` for any of the seven zone images;
* no `build:` stanza in the zone compose (all seven are pulls);
* no workflow invoking `docker/build-push-action`, `docker buildx build` or
  `docker push` for these images — the only `ghcr.io` / `buildx` reference in the
  organisation is the compose file itself;
* `veeona-ops/Dockerfile` builds the ops bot (`ops-bot`, uvicorn on :8000), not a
  zone image;
* the only `deploy.yml` workflows are mkdocs deploys whose `image:` line names a
  runner image (`catthehacker/ubuntu:act-latest`), not a build step.

The seven zone services do not even have image sources in the repository to
build from. There is nothing to trigger.

## 7. Node state on nexus-core

Measured over non-interactive SSH as user `nexus` (member of the `docker`
group; no sudo used):

| Check | Result |
| --- | --- |
| `curl -s -o /dev/null -w '%{http_code}' https://ghcr.io/v2/` | `401` — network path to GHCR is up |
| `docker images \| grep -i veeona` | none cached |
| `$HOME/.docker/config.json` | absent — no GHCR login on the node |
| Docker engine | `29.2.1` |

A read-only before-capture was taken (this lane creates and pulls nothing), to be
diffed against an after-capture:

```
date -u       2026-09-24T18:17:30Z
docker ps -a  grid-minio grid-core-n8n grid-core-n8n-worker grid-postgres grid-redis (+ faigrid-supervisor)
incumbents    Id / StartedAt / RestartCount captured for all five; RestartCount=0
              grid-core-n8n, grid-core-n8n-worker, grid-postgres  StartedAt 2026-03-25
              grid-redis  StartedAt 2026-03-25; grid-minio  StartedAt 2026-09-08
networks      compose_grid_net sha256 906a3b8edb8c1cab95b1bb1e41bb3d0ac3d5ce5ec6cdafb7a86ace4c62c91ffa
              (identical to the value recorded in the tenant round)
```

Because no pull could run, no image digest exists to record and there is no
per-image `docker pull` output. That is a consequence of §4, not an omission.

## 8. Verdict per acceptance criterion

| # | Criterion | Verdict | Evidence |
| --- | --- | --- | --- |
| 1 | Established with evidence whether the seven images exist — with credentials or from the build pipeline, never by inference from a 401 | **MET** | Authenticated registry reads (§3.1) return `404 MANIFEST_UNKNOWN` for all seven under both `veeona` and `veeona-ai`, while the private control returns `403 DENIED` and the public control returns `200`. No build pipeline exists (§6). Conclusion: the seven images do not exist. |
| 2 | If they exist: the node authenticates and `docker pull` succeeds for all seven, recorded per image | **NOT APPLICABLE** | The antecedent is false — the images do not exist, so no pull was possible. No digest exists to record. |
| 3 | If they do not: the veeona pipeline is triggered once and the same per-image pull proof follows | **NOT MET** | The images do not exist, but there is no veeona pipeline to trigger (§6), and no GHCR `write:packages` credential and no target namespace to publish into. Per the lane precondition, this is a STOP-and-report: the missing prerequisite is stated below rather than worked around. No image was fabricated, no namespace was created, no repository was written. |

## 9. What is missing (STOP report)

To move GO-003 past this point, one of the following must be supplied by an
operator or a separate build lane — none of it is performable from inside this
lane's write surface:

1. **A build pipeline for the seven zone images.** There is no Dockerfile and no
   image source in the veeona repositories today. This is net-new construction,
   not a trigger.
2. **A GHCR credential with `write:packages`** (and an existing target
   namespace) to publish the images once built. The available credential has
   `gist, read:org, repo` only.
3. **A decision on the namespace.** The compose pins `ghcr.io/veeona`, but the
   only veeona GitHub organisation is `Veeona-AI` (lowercased `veeona-ai`). The
   compose prefix and the publish target must be reconciled by veeona.

Until (1) exists, criterion 3 cannot be satisfied by any lane: the trigger has no
target.

## 10. Reproduction

The registry probes are credential-dependent and read-only; they write nothing.
They never print the token.

```bash
# positive and private controls, then the seven (as declared and as lowercased org)
acct=$(gh auth token >/dev/null; gh api user --jq .login)
TOKEN=$(gh auth token)

probe() {  # probe <owner/name> <tag>
  local repo="$1" tag="$2" tok
  tok=$(curl -s -u "${acct}:${TOKEN}" \
    "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))')
  curl -s -o /tmp/body.json -w '%{http_code}\n' \
    -H "Authorization: Bearer ${tok}" \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://ghcr.io/v2/${repo}/manifests/${tag}"
  cat /tmp/body.json | head -c 200; echo
}

probe actions/actions-runner latest      # -> 200
probe fusionaize/faigate latest          # -> 403 DENIED (private control)
for n in grid-edge control-plane research-runner production-runner \
         knowledge-graph publish-runner quarantine-sandbox; do
  probe "veeona/${n}"    0.1.0           # -> 404 MANIFEST_UNKNOWN
  probe "veeona-ai/${n}" 0.1.0           # -> 404 MANIFEST_UNKNOWN
done
```

Build-pipeline absence check (read-only):

```bash
cd /path/to/veeona/veeona
grep -rn 'ghcr\|buildx\|build-push-action' --include='*.yml' --include='*.yaml' .
# only deploy/zones/docker-compose.zones.yml matches
```

Node-side checks (read-only, no sudo):

```bash
ssh -o BatchMode=yes nexus-core 'curl -s -o /dev/null -w "%{http_code}\n" https://ghcr.io/v2/'
ssh -o BatchMode=yes nexus-core 'docker images | grep -i veeona || echo NONE_CACHED'
ssh -o BatchMode=yes nexus-core 'test -f $HOME/.docker/config.json && echo present || echo ABSENT'
```

## 11. Provenance

| Item | Value |
| --- | --- |
| Date | 2026-09-24 |
| faigrid branch / base | `docs/veeona-image-delivery` from `origin/dev` |
| faigrid base SHA | `ff7efabf09c726b243546852dfe85cfd49f906f2` |
| veeona compose revision | repo `78135fa35b5dd74d0d8ee9bcbdb0bbe433c3705c`; file last changed `9b22265` (2026-09-17) |
| veeona compose sha256 | `b449cf40ebffa7bb47778b95c5e46c7d0aeac076cb81087a79c1cd58b990f576` |
| Registry read credential | github.com `typelicious`; scopes `gist, read:org, repo` |
| Node | `nexus-core` 192.168.178.20, user `nexus`, Docker 29.2.1 |

No secret is recorded here; the credential is referenced by account and scope
only. The veeona repository was read, never modified.
