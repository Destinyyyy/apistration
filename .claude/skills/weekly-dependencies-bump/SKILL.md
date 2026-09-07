---
name: weekly-dependencies-bump
description: Triage, validate and merge the open Dependabot pull requests on datagouv/apistration. Handles the green minor/patch bumps end to end, flags major bumps for a human decision, and repairs the rubocop bumps whose new cops break the Lint job. Triggers — "check les PRs dependabot", "merge les dependabot", "bump hebdo des dépendances", "weekly dependencies", "les PRs de mise à jour de gems", "rubocop bump rouge".
---

# Weekly Dependencies Bump

Routine pass over the open Dependabot PRs. The goal is zero open Dependabot PR
at the end, or an explicit question to the user for the ones that cannot be
decided alone.

## Decision rules

1. **Green + no major bump** → approve and merge, no questions asked.
2. **Green + major bump** → read the changelog and the diff. Merge only if the
   breaking changes provably do not touch this codebase; otherwise ask.
3. **Red on Lint only, rubocop bump** → fix it (see below), then merge.
4. **Red on anything else** → investigate, and ask before merging.

A grouped PR (`bump the development-dependencies group ... with N updates`)
holds several gems: read the body and apply the rules to *every* gem in it.

## Triage

```bash
gh pr list --author "app/dependabot" --limit 50 \
  --json number,title --jq '.[] | "\(.number)\t\(.title)"'

for pr in <numbers>; do
  echo "=== $pr ==="
  gh pr view $pr --json title,mergeable,mergeStateStatus,statusCheckRollup \
    --jq '"\(.title)\n\(.mergeable) \(.mergeStateStatus)\n" +
          ([.statusCheckRollup[] | "\(.name // .context): \(.conclusion // .state)"] | join("\n"))'
done
```

`mergeStateStatus: BLOCKED` on a fully green PR just means the review is
missing — approving unblocks it. `SKIPPED` deploy jobs are normal on a branch.

For a grouped or major bump, read the changelog Dependabot embeds in the body:

```bash
gh pr view <pr> --json body --jq .body
```

## Merging

```bash
gh pr review <pr> --approve && gh pr merge <pr> --merge
```

Merge commits, not squash — that is the repo's history style. Verify
afterwards, `gh pr merge` stays silent on success:

```bash
gh pr view <pr> --json number,state,mergedAt
```

## Repairing a rubocop bump

A rubocop minor release ships new cops; the pre-existing code violates them and
the `Lint` job turns red. The fix is mechanical, but it edits application code,
so it needs a real checkout and a local verification — never push a blind
autocorrect.

There is one rubocop PR per app (`/siade` and `/site`), each with its own
`Gemfile`. Handle them one at a time.

Read the failure first, to confirm it is only new-cop noise:

```bash
branch=$(gh pr view <pr> --json headRefName --jq .headRefName)
run=$(gh run list --branch "$branch" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$run" --log-failed | grep -iE "offense|\.rb:[0-9]+" | head -40
```

Then work in a throwaway worktree, so the main checkout keeps its branch:

```bash
git fetch origin
git worktree add "$SCRATCHPAD/rubocop-siade" dependabot/bundler/siade/rubocop-xxxxxxxx
cd "$SCRATCHPAD/rubocop-siade/siade"   # or .../site for the site PR
bundle install
bundle exec rubocop -a
```

`-a` (safe autocorrect) is the first attempt. Several style cops — including
`Style/DirectiveScope`, the one that broke the 1.90.0 bump — are marked unsafe
and only `-A` corrects them. `-A` is acceptable **only** when followed by a
clean verification run:

```bash
bundle exec rubocop -A
bundle exec rubocop          # must end on "no offenses detected"
git -C .. diff               # eyeball a few hunks: the rewrite must be a no-op
```

Then commit and push:

```bash
git -C .. status --short | grep -v '^ M siade/'   # nothing outside the app
git -C .. add -A
git -C .. commit -m "Linting"
git -C .. push
```

Wait for the CI, then approve and merge as usual:

```bash
until [ "$(gh pr checks <pr> --json bucket --jq '[.[] | select(.bucket=="pending")] | length')" = "0" ]; do
  sleep 20
done
gh pr checks <pr> --json name,bucket --jq '.[] | "\(.name): \(.bucket)"'
```

Finally, clean up:

```bash
git worktree remove --force "$SCRATCHPAD/rubocop-siade"
git branch -D dependabot/bundler/siade/rubocop-xxxxxxxx
```

## Key facts (do not relearn)

- The Dependabot author filter is `app/dependabot`, not `dependabot[bot]`.
- Dependabot groups are configured per app: `rubocop`,
  `development-dependencies`, `production-dependencies`. The group name is in
  the PR title and tells you the blast radius.
- The commit message for a lint repair is exactly `Linting`.
- `Style/DirectiveScope` rewrites a `disable` / `enable` pair around a single
  statement into `disable-next`. `disable-next` covers the whole next
  expression, multi-line methods included — unlike `disable-next-line`. That is
  why its autocorrect is safe in practice despite being flagged unsafe.
