# RFL-022 finding: does the config or FAI-229 describe the live release flow?

## Question

`fusionaize-ops/config.yml` disables `release` for `faigrid` (`enabled: false`, FRL-008,
2026-09-23), while planning ticket FAI-229 says faigrid's release flow moved onto
ops-engine 3.4.2. One of the two is right. This document measures which one describes
the live flow, and names the evidence for every claim.

It also records the second half of the lane: with the answer known, the layover config
and faigrid's own workflow must declare exactly one writer of the release object.

Everything below was measured read-only from this worktree (faigrid at
`ec4c2395cf09542deaf6836afe9921d921681dda`) and from the `fusionaize-ops` worktree at
`314f77c51d5db5eb3847ef648364691b173e983b`. FAI-229's own text was read from
`fusionaize-planning` (`.skillweave/planning/done/FAI-229-faigrid-release-flow-onto-ops-engine-342.md`
and `.skillweave/planning/prds/FAI-229-release-flow-ops-engine-342/prd.md`). No host was
touched, no tag was pushed, no service was restarted.

## Answer

**FAI-229 describes the live flow.** The live flow is the repository-local producer
`.forgejo/workflows/forgejo-release.yml`, which pins ops-engine v3.4.2, runs a `gate`
job and a `release` job with `needs: gate`, and publishes through
`ReleaseHandler.publish_release` over both destinations in `.ops.yaml`.

`enabled: false` in the layover config is **not** a claim about that producer. It is a
claim about *the layover's own* role as a producer, and it is true: the deployed layover
runs ops-engine 2.0.0, writes one forge with a `<repo> <tag>` name, and would be a
second, competing writer on the same tag. This is not an inference: it is FAI-229's own
FRL-008, whose option 2 chose exactly this disable and required the repo-local workflow
named as the producer (B4). The contradiction the PRD names is therefore a collision
between the ticket's first half and its last unit, not two contradictory facts about the
live flow: the config says "the layover is not the producer", and a reader takes that to
mean "no engine path produces".

The defect that this leaves in the tracked tree is real and is what the lane fixes: the
config block is the only place an operator reads faigrid's release role, and it states
`enabled: false` next to a `name_template` and a `trigger` — the shape of a
release-enabled entry — while FAI-229 says the engine path is the producer. Criterion 2
resolves it by putting the layover in line with the one writer that is live.

## Belegt (measured)

### B1 — The live producer on Forgejo is the repo-local engine workflow

Every release object on the Forgejo canonical forge from `v1.8.7-rc1` onward was created
at the second the `forgejo-release.yml` `release` job ran, and was created by the token
the workflow uses.

Commands (inside this worktree, token from the environment):

```
curl -sS -H "Authorization: token $FORGEJO_TOKEN" \
  'https://git.langevc.com/api/v1/repos/fusionaize/faigrid/releases?limit=30'
curl -sS -H "Authorization: token $FORGEJO_TOKEN" \
  'https://git.langevc.com/api/v1/repos/fusionaize/faigrid/actions/tasks?limit=200'
```

Result (raw, unabridged, in the attempt evidence file `e-forgejo-releases.log` and
`e-workflow-runs.log`):

| tag | release id | author login | title | release created | `release` job created |
| --- | --- | --- | --- | --- | --- |
| v1.10.1 | 378 | Ghost (token user) | fusionAIze Grid v1.10.1 | 2026-09-25T16:26:27+02:00 | 2026-09-25T16:26:38+02:00 |
| v1.10.0 | 377 | Ghost | fusionAIze Grid v1.10.0 | 2026-09-25T16:03:17+02:00 | 2026-09-25T16:03:28+02:00 |
| v1.9.0 | 375 | Ghost | fusionAIze Grid v1.9.0 | 2026-09-24T13:25:32+02:00 | 2026-09-24T13:25:42+02:00 |
| v1.8.9-rc1 | 374 | Ghost | fusionAIze Grid v1.8.9-rc1 | 2026-09-23T09:38:06+02:00 | 2026-09-23T09:42:20+02:00 |
| v1.8.7-rc1 | 367 | Ghost | fusionAIze Grid v1.8.7-rc1 | 2026-09-23T05:20:24+02:00 | 2026-09-23T05:20:36+02:00 |

The release `created_at` precedes the job's `created_at` by seconds because Forgejo
stamps the job record when the runner registers it; the binding is that each release
appears only after its `release` job started and its title is exactly the
`.release-title-prefix` value (`fusionAIze Grid`) rendered by the workflow's title gate,
not the engine 2.0.0 `<repo> <tag>` form FRL-008 measured.

The last human/legacy object is `v1.8.0` (id 319), author `dev.bot_fusionaize` (uid 16,
the `fusionaize-ops-token` account), `target_commitish: main`, at 2026-08-22T14:51:47+02:00.
The producer workflow file is not present in that tag (B3).

### B2 — The producer pins ops-engine 3.4.2 and publishes through `ReleaseHandler.publish_release`

`.forgejo/workflows/forgejo-release.yml` (present at the worktree tip):

- header: "Production releases are cut here, on Forgejo, by the ops-engine ReleaseHandler
  — the GitHub mirror does distribution only and never writes a release object";
- `on: push: tags: ["v*.*.*"]` plus `workflow_dispatch` with `tag_name`;
- `gate` job: title gate against `.release-title-prefix` (`fusionAIze Grid`), CHANGELOG
  section, audience gate; `release` job with `needs: gate`;
- the engine is installed from `git+https://github.com/LangeVC/ops-engine@v3.4.2`, a
  runtime version gate `REQUIRED = "3.4.2"` refuses any other version, and the publish
  step calls `await ReleaseHandler.publish_release(...)` over the destinations parsed
  from `.ops.yaml`.

### B3 — The producer is absent before `v1.8.7-rc1` and present from it on

```
for t in v1.7.0 v1.8.0 v1.8.9-rc1 v1.9.0 v1.10.1; do
  git cat-file -e "$t:.forgejo/workflows/forgejo-release.yml"; echo "$t EXIT=$?"
done
```

```
v1.7.0 EXIT=128
v1.8.0 EXIT=128
v1.8.9-rc1 EXIT=0
v1.9.0 EXIT=0
v1.10.1 EXIT=0
```

The workflow file was added by `e069697` (2026-09-23 01:55:35 +0200,
`feat(release): add .forgejo/workflows/forgejo-release.yml`). The mirror stopped
producing with `e8ae253` (2026-08-23 03:00:07 +0200,
`feat(release): stop producing releases on the GitHub mirror`, which removed
`.github/workflows/release-please.yml`, `release-please-config.json` and
`.release-please-manifest.json`). `v1.8.0` is therefore the gap: no mirror producer
(removed 2026-08-23), no Forgejo producer yet (added 2026-09-23).

### B4 — The FAI-229 ticket exists, and its own FRL-008 is what set `enabled: false`

FAI-229 is a closed ticket in `fusionaize-planning`, in two documents:

- `.skillweave/planning/done/FAI-229-faigrid-release-flow-onto-ops-engine-342.md` (status
  `done`, closed 2026-09-23);
- `.skillweave/planning/prds/FAI-229-release-flow-ops-engine-342/prd.md` and `sequences/`.

The ticket's subject is *"faigrid release flow onto ops-engine 3.4.2 — install the producer
FFR-600-2 declared"*. Its eight units are FRL-001 to FRL-008. **FRL-008** (`prd.md:112-120`)
is the unit that produced the `enabled: false` line this lane exists to reconcile:

> FRL-008 — Resolve the layover's role for faigrid (repo: fusionaize-ops) ... Two configured
> producers on one tag is a risk this round must not inherit.
> - 2 — faigrid's layover `release` block is either kept with a recorded reason why two
>   producers are safe, or set to `enabled: false` with the repo-local workflow named as the
>   producer.
> - 3 — Whichever is chosen is written into `docs/release-path.md`, so the next reader does
>   not re-derive it.

So the config's `enabled: false` is not opposed to FAI-229. It **is** FAI-229's own output:
option 2 of FRL-008 chose the disable and named the repo-local workflow as the producer. The
contradiction in the PRD's task title ("release disabled vs FAI-229") is between the *ticket's
first half* (install the engine producer) and the *ticket's last unit* (disable the layover),
both of which shipped. The live flow is the engine path; the config records that the layover
is not a second writer of it. Both statements are true at once.

The ticket also records, in "What the round actually found", that the deployed layover ran
**ops-engine 2.0.0** on `langevc-prod-01` and that the layover's silence was deployment drift,
not configuration — the same fact FRL-008's `config.yml` comment carries.

The faigrid-side commits that record the outcome agree: `cb8732e` and `da5b135`
(2026-09-23 11:37:38 +0200) changed `AGENTS.md`; `da5b135`'s body reads "The layover is not
faigrid's producer: FRL-008 set its release block to enabled: false ... The producer is this
repository's `.forgejo/workflows/forgejo-release.yml`. release-please is removed, not legacy."
The ticket in `fusionaize-planning` is the primary text; these commits are its record in-tree.

### B5 — No other release-object writer exists in faigrid's workflows

```
grep -nE 'gh release|action-gh-release|/releases|publish_release|create_release|createRelease' \
  .forgejo/workflows/*.yml .github/workflows/*.yml
```

Five matches, all in `.forgejo/workflows/forgejo-release.yml` and all on the
`publish_release` path (three are comments explaining that path, one names the GitHub
adapter's `create_release` call that `publish_release` performs). One match in
`.github/workflows/notify-tap.yml:56` is `gh release view ... --json tagName`, a read.

`mirror.yml`, `ci.yml`, `visibility-gate.yml` and the health workflows write no release
object. The mirror is a writer of git refs only, which is the intended split.

### B6 — Both forges carry the same object, produced from the Forgejo side

`v1.10.1` on GitHub (mirror) and on Forgejo (canonical):

| field | GitHub | Forgejo |
| --- | --- | --- |
| tag | v1.10.1 | v1.10.1 |
| title | `fusionAIze Grid v1.10.1` | `fusionAIze Grid v1.10.1` |
| body head | `### Bug Fixes` | `### Bug Fixes` |
| publisher | `dev-bot-fusionaize` (GitHub app) | token user of the workflow |

The GitHub release is created by `publish_release`'s GitHub destination in `.ops.yaml`,
not by a GitHub workflow: the mirror's `notify-tap.yml` only reads it. This is the
"one release object per destination, publisher is the engine bot" shape RFL-002 narrowed.

## Plausibel (supported, not proven here)

- **P1 — FAI-229's "ops-engine 3.4.2" is the same pin as `.forgejo/workflows/forgejo-release.yml`.**
  FAI-229's subject names 3.4.2 and its FRL-003 criterion 3 requires the workflow "engine
  pinned and asserted at v3.4.2"; the workflow's runtime gate is `REQUIRED = "3.4.2"` (B2).
  The ticket states the pin explicitly, so this is agreement of two texts rather than an
  inference.
- **P2 — The `Ghost` author on Forgejo is the API token user, not an anonymous actor.**
  Forgejo reports `Ghost` with `id: -1` for releases created by a token whose user record
  is not resolvable through the release API. The binding to the workflow is the timing
  and title in B1, plus B2/B5 showing no other writer. A delivery log from the layover
  would settle it; the layover is disabled for faigrid and its log was not read (out of
  this lane's work surface).
- **P3 — The layover would be a second producer if enabled.** This rests on FRL-008's
  measurement of ops-engine 2.0.0 (`_create_release_for_tag` writes one forge, name
  `<repo> <tag>`) and on `src/handlers/webhook_handler.py:66` in `fusionaize-ops`, which
  runs `ReleaseHandler.process_event` whenever `release.enabled` is true. The deployed
  engine version is the operator's measurement, not re-measured here.

## Unbestaetigt (not established by this measurement)

- **U1 — Why the layover's webhook deliveries for faigrid never produced a release.** FRL-008
  records 502s from a crash-looping bot on an empty `GITHUB_WEBHOOK_SECRET`. That is a
  statement about 2026-09-23; whether it still holds, and whether a re-enabled layover
  would now publish, is a runtime question this lane does not answer.
- **U2 — Whether `v1.8.0`'s body matches any engine's output.** FRL-008 says it does not
  match ops-engine 2.0.0's shape; the body starts `### Bug Fixes`, which is also the shape
  the repo-local gate produces. The object predates the repo-local producer (B3), so it
  cannot have come from it. Its exact origin is not established here.
- **U3 — Whether the layover's `config.yml` bind mount on the running host matches this
  worktree.** `docs/layover-redeploy.md` in `fusionaize-ops` states the deployed copy
  predates FRL-008's `enabled: false`. The deploy distance is an operator step.

## Consequence for the lane

- **Criterion 1** is answered: FAI-229 describes the live flow; the `enabled: false` line
  describes only the layover's role and is misread as the repository's release status.
- **Criterion 2** follows from the answer. The one live writer is the engine path
  (`ReleaseHandler.publish_release` in `.forgejo/workflows/forgejo-release.yml`). The
  layover must therefore not be release-enabled for faigrid; that is FAI-229's FRL-008
  option 2, and enabling it would add the second writer FRL-008 forbids. This lane's
  write surface is `fusionaize-ops:config.yml` and its tests only — the workflow is not
  in it — so the config stays the non-writer and must *declare* the workflow as the one
  writer unambiguously.
- **Criterion 3** requires that a config test fails against the base. It does, twice
  over: the tracked `tests/test_faigrid_release_config.sh` asserts `release.enabled is
  true` (FFR-600-6, 2026-08-23, before FRL-008) and fails against a block that FRL-008
  set to `false`; and the same block still carries `trigger: "tag_push"` under a
  disabled `release:`, the "shape of a release-enabled entry" this finding opens with.
  Both are the stale declaration, not a stale fact. The red proof and the corrected
  assertion are the ops side of this lane.
