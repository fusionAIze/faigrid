# Release path

## Question

Does release-please actually run on the GitHub mirror — or only on Forgejo, or
on both? This document answers that question from evidence, not from inference
about the workflow configuration.

## Finding

**Release-please actually ran on the GitHub mirror** for releases 1.6.1, 1.6.2
and 1.7.0. **It did not produce 1.8.0** — that release was committed and tagged
by a human, with a git-cliff changelog.

There is exactly one release producer configured (the GitHub mirror), and the
git history confirms it actually ran there.

## Configuration evidence: single producer by construction

The release producer is defined in exactly one place:

- `.github/workflows/release-please.yml` is the only workflow that invokes
  `googleapis/release-please-action` (line 21). No other workflow file
  references `release-please-action`.
- That job is gated to GitHub only: `if: ${{ github.server_url == 'https://github.com' }}`
  (line 13). The follow-up `notify-tap` job carries the same guard (line 31).
  On Forgejo, `github.server_url` is the Forgejo URL, so Forgejo skips the
  workflow entirely.
- `.forgejo/workflows/` contains only `mirror.yml`, a push-only mirror that
  force-pushes branches and tags to GitHub. It references no release-please
  action, so Forgejo is not a second producer.

This configuration is what makes the mirror the single release producer. But
configuration alone is inference; the runtime evidence is below.

## Runtime evidence: what the git history actually shows

Release-please runs as `github-actions[bot]` when it uses `GITHUB_TOKEN`, and it
emits commits with the subject `chore(main): release X.Y.Z`. Those two markers
are the observable signature of a real release-please run on GitHub.

| Release | Tag commit | Author | Date | Producer |
| --- | --- | --- | --- | --- |
| 1.6.1 | `430c595` | `github-actions[bot]` | 2026-04-03 | release-please (`chore(main): release 1.6.1 (#10)`) |
| 1.6.2 | `553c133` | `github-actions[bot]` | 2026-04-14 | release-please (`chore(main): release 1.6.2 (#13)`) |
| 1.7.0 | `74d69fa` (also `918def0`) | `github-actions[bot]` | 2026-04-14 | release-please (`chore(main): release 1.7.0 (#15)`) |
| 1.8.0 | `3520451` (also `ba1a831`) | André Lange (human) | 2026-08-22 | manual — `chore: release 1.8.0` |

The tags `v1.6.1`, `v1.6.2` and `v1.7.0` each point to a commit authored by
`github-actions[bot]` with the `chore(main): release …` subject. That is direct
evidence that release-please produced those releases, and — because
`github-actions[bot]` is GitHub's own bot identity, not a Forgejo identity —
that it ran on the GitHub mirror, not on Forgejo.

The 1.8.0 tag instead points to `3520451`, a commit authored by a human with the
subject `chore: release 1.8.0` (no `(main)` scope, no PR number). The changelog
header also changed: `CHANGELOG.md` now states "Generated from conventional
commits using git-cliff" and a `.cliff.toml` is present. Both facts show 1.8.0
was cut manually, outside release-please.

## Conclusion

- Evidence (not inference): release-please has actually run on the mirror —
  1.6.1, 1.6.2 and 1.7.0 were produced by `github-actions[bot]`.
- Evidence (not inference): release-please did not produce the current 1.8.0 —
  it is a manual, human-authored release with a git-cliff changelog.

The single-producer property is enforced by `tests/test_single_release_producer.sh`.
