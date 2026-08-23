# Release path

## Question

Where does faigrid cut releases, through which producer, and how does a release
reach the Homebrew tap without leaking writes back onto a mirror that is
supposed to stay a one-way copy? This document answers that from evidence, not
from inference about the workflow configuration.

## The division (FFR-600)

faigrid has exactly **one** release producer, and it is the **GitHub mirror**
via `release-please`. The canonical Forgejo origin is *not* a second producer:
its only output toward GitHub is the push-only `mirror.yml` sync. There is one
producer by construction and by runtime evidence.

| Aspect | Canonical (Forgejo) | Mirror (GitHub) |
| --- | --- | --- |
| Role | source of truth, canonical history | release producer + read-only public mirror |
| Release producer | none | release-please (single) |
| Tap distribution | n/a | `release.published` -> homebrew-tap |

## Single producer

The release producer is defined in exactly one workflow:

- `.github/workflows/release-please.yml` is the only workflow that invokes
  `googleapis/release-please-action` (line 21). No other workflow file
  references `release-please-action`.
- That job is gated to GitHub only: `if: ${{ github.server_url == 'https://github.com' }}`
  (line 13). On Forgejo, `github.server_url` is the Forgejo URL, so Forgejo
  skips the workflow entirely.
- `.forgejo/workflows/` contains only `mirror.yml`, a push-only mirror that
  force-pushes branches and tags to GitHub. It references no release-please
  action, so Forgejo is not a second producer.

### Runtime evidence

Release-please runs as GitHub's Actions bot. Its identity is
`github-actions[bot]` (older releases) and, after GitHub renamed the bot,
`app/github-actions` (more recent runs). Its commit subject is
`chore(main): release X.Y.Z`. Those two markers are the observable signature
of a real release-please run on GitHub.

| Release | Author | Producer |
| --- | --- | --- |
| 1.6.1 | `github-actions[bot]` | release-please (`chore(main): release 1.6.1 (#10)`) |
| 1.6.2 | `github-actions[bot]` | release-please (`chore(main): release 1.6.2 (#13)`) |
| 1.7.0 | `github-actions[bot]` | release-please (`chore(main): release 1.7.0 (#15)`) |
| 1.8.0 | human | manual, git-cliff changelog |

The GitHub PR list confirms the producer directly: PRs #10, #13, #15 are
`chore(main): release …` authored by the bot identity, and PR #22
`chore(main): release 1.7.1` is authored by `app/github-actions`. All of these
came from release-please running on the mirror.

## Homebrew tap distribution (post-mirror)

Two wiring paths deliver a release to the Homebrew tap, both gated to
`github.com` so they fire only on the mirror, after the release lands there:

1. `.github/workflows/notify-tap.yml` — triggers on the GitHub
   `release: published` event. Its single job
   (`if: github.server_url == 'https://github.com'`) computes the release
   archive SHA256 and, via `actions/github-script`, dispatches a
   `formula-update` repository-dispatch event to
   `fusionAIze/homebrew-tap` with `{ formula: "faigrid", version, sha256 }`.

2. `.github/workflows/release-please.yml`'s `notify-tap` job — the fallback
   that runs only when release-please actually created the release
   (`release_created == true`). It repeats the same SHA256 computation and
   dispatch with a dedicated `TAP_GITHUB_TOKEN`.

The standalone `notify-tap.yml` is the primary path: it is keyed on the GitHub
`release.published` event, which is the canonical "a release now exists on the
mirror" signal, independent of which tool produced it. This is what keeps the
tap working even when 1.8.0 was cut by a human instead of release-please.

## Writes back onto the read-only mirror

The mirror is a *recovery copy* (see `mirror.yml` header comments): its
contract is one-way, Forgejo -> GitHub. release-please is deliberately allowed
to be the *one* exception — it runs on GitHub and writes release commits,
branches, and PRs there. The rule is that those writes are **resolved**, not
tolerated, into the canonical line:

- release-please's release commits and tags flow back into the canonical
  Forgejo history (they appear on `origin/main` and as tags `v1.6.1`,
  `v1.6.2`, `v1.7.0`). A release-please run is only complete when its output
  is reconciled onto Forgejo.
- A release-please run that is **left open** is tolerated-write residue and
  must be closed. Concrete case: PR #22 `chore(main): release 1.7.1`
  (opened by `app/github-actions` on 2026-06-30) was never merged — the
  release line moved on to a manual 1.8.0 instead. Its head branch
  `release-please--branches--main` is still present on both `origin` and the
  mirror. That open PR and its branch are the residue this document flags for
  resolution.
- Release tags must stay identical across the two remotes. Observed
  discrepancy to resolve: `v1.8.0` is an *annotated* tag object (`976adfc`)
  on Forgejo but a *lightweight* tag pointing straight at commit `3520451` on
  GitHub — the annotated tag object itself was never mirrored.

`tests/test_single_release_producer.sh` encodes the invariants that make this
division enforceable: a single producer gated to GitHub, a tap dispatch wired
on the release event, and no second producer on Forgejo.
