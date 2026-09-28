---
description: use when the user asks to monitor, watch, or babysit a PR
---

# Babysit PR Skill

## Monitoring & CI Loop
- Use harness tools to monitor PR activity if available; otherwise, poll for new review comments and CI status checks. Prefer `gh`; `gh api` reaches the review-thread endpoints the porcelain commands do not.
- Watch feedback from **every** reviewer — human reviewers, review threads, review states, inline comments, issue comments, and any bot (`coderabbitai`, `github-advanced-security`, `sonarcloud`, `codecov`, `renovate`, custom org bots, …). Do not filter by author; a finding counts no matter who left it.
- Only process checks and review comments that are **newer than the latest push**.
- Keep an eye on changes to `main` and rebase as needed to keep the branch fresh.
- Loop verify → group → fix → single push per batch until no outstanding comment needs action, all CI checks pass green, and all required approvals are secured (by a human or by whichever bot gates the repo).
- Stop immediately if the PR is closed or merged, even with checks or approvals outstanding, and report that terminal state.

## Handling Feedback & Failures
- **Verify every finding against the current code** before modifying anything. Drop the ones that are outdated, already fixed, purely stylistic noise the repo does not follow, or wrong — note the reason, you will reply with it.
- Treat line numbers in review comments as hints only.
- Fix genuine bugs and CI failures, distinguishing repository issues from infrastructure flakes.
- Keep changes minimal — fix the finding, not the surrounding code.
- If a fix changes what deployment needs (a new migration, env var, queue, or manual command), update the PR body's Deployment, Runbook, and Merge Checklist sections to match.
- If a required fix is genuinely ambiguous or blocked, ask one brief question instead of guessing.
- If an overriding pull request makes this PR obsolete, stop monitoring, report to the user, and ask before closing.

## Fix Batches
- Group surviving findings into fix units. One fix unit = one distinct change plus the exact set of files it will touch. Merge two findings into the same unit when they touch a common file or are two symptoms of one root cause.
- One push per batch, after every fix for that batch is committed. Never push mid-batch.

### Parallel fixes
- Units whose file sets are disjoint run **concurrently**, one subagent per unit, all launched in a single message.
- Units that share a file are **not** parallel. Chain them into one subagent that handles them in sequence, or run them yourself after the parallel batch returns. Two agents editing one file will clobber each other.
- With fewer than three units, or when every unit touches the same area, skip the fan-out and do the work inline. Spawning agents costs more than it saves on small batches.
- Give each subagent: the verbatim comment(s), the reviewer, the file/line hints, the file set it owns, and the instruction that it owns those files exclusively and must not touch anything else.
- Each subagent investigates the finding against current code, makes the smallest correct change, runs whatever targeted check the repo offers for that code, then commits **only its own files** with `git commit -m <msg> -- <path>…` (path-scoped, so it never picks up another agent's work). Never `git add -A`, never `git add -u`, never `git push`.
- `.git/index.lock` contention is expected when commits land at once. A subagent that hits it waits a second and retries, up to a few times.
- A subagent reports back what it changed and the commit sha, or that the finding turned out to be invalid and it committed nothing.
- After every subagent returns, review the combined diff yourself before pushing. Agents can be individually right and collectively wrong.

## Replying In-Thread
- Answer every finding **inside its own review thread** — what was fixed and in which commit, or the concrete reason it was skipped (already fixed in `<sha>`, the code does X not Y, the repo deliberately does it this way). A bare "done" leaves the next reader guessing.
- `gh pr comment` posts to the conversation tab and does not reach any thread. Reply to an inline comment with
  `gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies -f body='…'`,
  using the `id` of the **first** comment in that thread (a reply's own id will not do).
- Enumerate open threads with
  `gh api graphql -f query='{repository(…){pullRequest(number:N){reviewThreads(first:100){nodes{id isResolved comments(first:1){nodes{databaseId path line body author{login}}}}}}}}'`.
  `gh pr view` flattens them and loses the thread grouping. Skip nodes where `isResolved` is already true.
- Only a review's top-level summary body, which has no file or line, has no thread to answer in. That one, and only that one, gets a plain PR comment.
- **Never resolve a thread.** Reply and leave it open — the reviewer who raised it, or another human, decides when it is settled. `resolveReviewThread` is off limits.

## Comment Formatting & Media
- Format comments posted on the maintainer's behalf as follows:
  `<!-- model: <slug> --> responding on behalf of <User>\n\n<reply>`.
- Embed screenshots or uploaded media links when visual evidence helps clarify the fix.

## Scope Constraint
- **Do not allow review feedback to expand the PR beyond the original goal.** Address genuine issues, but strictly prevent scope creep.
