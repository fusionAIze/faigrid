# Release path

## Question

Where does faigrid cut releases, through which producer, and how does a release
reach the Homebrew tap when the GitHub mirror is read-only by contract? This
document answers that from evidence and from the operator decision recorded in
FFR-600-2.

## The operator decision (FFR-600-2, 2026-08-23)

faigrid follows the standard fusionAIze model without exception:

```
local -> Forgejo (canonical) -> mirror -> GitHub does distribution only
```

Production releases are produced **on Forgejo** by the ops-engine
`ReleaseHandler` (`release.enabled` + `name_template`). The GitHub mirror stops
being a producer. It retains exactly one downstream-side responsibility:
distribution to the Homebrew tap, keyed on the release tag that mirror.yml
copies verbatim from Forgejo.

This makes faigrid conform to the shape FAI-211 already records for faigate's
`prerelease.yml` divergence: the mirror no longer writes releases, it only
distributes what the canonical producer cut.

## How it was (the divergence this decision closes)

Dispatch-1/2/3 evidence established that, before this change, the opposite was
true:

- release-please produced releases on the GitHub mirror (1.6.1, 1.6.2, 1.7.0
  by `github-actions[bot]`; 1.8.0 manually by a human).
- There was **no** Forgejo producer.
- The read-only mirror was being written to: open PR #22 for release 1.7.1 and
  its branch `release-please--branches--main` were left open by a
  release-please run.

That evidence stands. The target state below replaces the mechanism, not the
record.

## Target state: one producer, on Forgejo

| Aspect | Canonical (Forgejo) | Mirror (GitHub) |
| --- | --- | --- |
| Role | source of truth + release producer | read-only public mirror + distribution |
| Release producer | ops-engine `ReleaseHandler` | none |
| Tap distribution | n/a | tag push -> homebrew-tap |

### One producer, reducible to two file facts

- `.github/workflows/release-please.yml` is **removed**. Nothing in this
  repository invokes `googleapis/release-please-action` anymore. Removal (not
  neutralization) is the only way to guarantee "no release object, no tag" is
  ever produced from the mirror, because a workflow that cannot exist cannot
  fire.
- `.github/workflows/notify-tap.yml` no longer contains a release-please
  fallback job. It triggers solely on the push of a `v*` tag to the mirror —
  the exact event `mirror.yml` emits when it copies the ops-engine's release
  tag across.

The release-please configuration files (`release-please-config.json` and
`.release-please-manifest.json`) are removed with the workflow. They are dead
configuration once the action is gone; leaving them would imply a producer
that no longer exists.

### How the tap is triggered now

`mirror.yml` (`.forgejo/workflows/mirror.yml`, which this change does not
touch) force-pushes every Forgejo tag matching `v*` to GitHub on the `push`
event. When the ops-engine cuts a release on Forgejo:

1. the ops-engine creates the annotated release tag `vX.Y.Z` on Forgejo,
2. Forgejo's `mirror.yml` push event copies that tag to GitHub,
3. GitHub sees the `vX.Y.Z` tag push and runs `notify-tap.yml`, which computes
   the source-tarball SHA256 and dispatches `formula-update` to
   `fusionAIze/homebrew-tap`.

The tap payload (`formula`, `version`, `sha256`) is unchanged; only the
trigger moved from "release-please output" to "mirrored tag".

### What breaks if the ops-engine release is absent

- If the ops-engine has not yet been configured to cut faigrid releases, no
  `v*` tag is produced on Forgejo, so none is mirrored, so `notify-tap.yml`
  never fires. **That is acceptable and intentional**: it is safe to produce
  no release (and no tap update) in the window between this change and the
  `fusionaize-ops` configuration. Nothing fails, nothing writes to the mirror.
- The tag shape is the contract: the ops-engine must produce an **annotated**
  tag so that a `v*` tag reaches the mirror. A tag that never lands on the
  mirror cannot trigger the tap, and a release that exists only on Forgejo is
  invisible to GitHub distribution until mirror sync runs.
- The `fusionaize-ops` configuration itself (`release.enabled`,
  `name_template` for the `ReleaseHandler`) is a *different repository* and is
  out of scope for this change. Until it lands, faigrid cuts no releases at
  all.

## Mirror-write residue: named, with a cleanup path, NOT executed here

The following are outward-facing on GitHub (deleting a branch, closing a PR).
They have visible effect and therefore belong to the operator, not to this
repository change. This section names them and the required action; it does
not perform them.

1. **Open PR #22** — `chore(main): release 1.7.1` (opened by
   `app/github-actions` on 2026-06-30), never merged. The release line moved
   on to a manual 1.8.0. **Action (operator):** close it on GitHub. It is a
   stale release-please artifact with no producer backing it anymore.
2. **Branch `release-please--branches--main`** — the head of that PR, present
   on both `origin` and the mirror. **Action (operator):** delete it from
   Forgejo; `mirror.yml`'s `prune=true` full-state dispatch then removes it
   from GitHub, restoring the one-way mirror contract.
3. **`v1.8.0` tag-shape drift** — `v1.8.0` is an *annotated* tag object
   (`976adfc`) on Forgejo but a *lightweight* tag pointing straight at commit
   `3520451` on GitHub; the annotated tag object was never mirrored.
   **Action (operator):** re-run a full-state `workflow_dispatch` of
   `mirror.yml` with the tag ref so the annotated object is mirrored verbatim,
   then verify `git ls-remote --tags` agrees across both remotes. This matters
   now because the tap fires on mirrored tags; a lightweight/annotated
   mismatch is exactly the class of drift that can make tag identity diverge.

Why these are operator actions rather than repository changes: deleting a
branch or closing a PR on GitHub is a mutation of live remote state, not of
the tracked tree. Doing it from a worktree change would conflate a source
edit with an external side effect, and would be impossible to review as a
single diff.

## Enforceability

`tests/test_single_release_producer.sh` encodes the target-state invariants:
there is **no** release producer on the mirror (release-please.yml absent, no
workflow references release-please-action), the tap is wired to the `v*` tag
push and gated to github.com with no release-please dependency, and Forgejo
remains without its own release-please producer. The earlier "runtime
evidence" assertions about release-please's historical commits are retired:
they prove the *past* producer, not the target state.
