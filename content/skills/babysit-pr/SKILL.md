---
description: use when the user asks to monitor, watch, or babysit a PR
---

# Babysit PR Skill

## Scripts
Both live in `scripts/` beside this file. `-R owner/repo` and `--pr N` default to the current branch's PR.

- `scripts/pr-watch` blocks until the PR needs attention, prints one summary (state, head SHA, checks with failing names, review decision, merge state, new comments and reviews, CodeRabbit rate limit), then exits. The first run prints at once; `--once` never blocks.
- `scripts/pr-threads list | reply THREAD_ID BODY | comment BODY | resolve THREAD_ID` handles review threads and PR comments. A `BODY` of `-` reads stdin; `--dry-run` prints instead of posting.

## Monitoring & CI Loop
- Every wait is `pr-watch` launched through the Bash tool with `run_in_background: true` and `timeout: 7200000`; its exit notification is your wake-up. It sleeps internally, which the harness allows. Run one per PR: a second one exits 3 and names the running PID.
- Post every reply and PR comment through `pr-threads`. Your comments post under the user's login; `pr-threads` records their IDs so `pr-watch` reports only feedback from others.
- Act on feedback from **every** reviewer — humans and any bot (`coderabbitai`, `github-advanced-security`, `sonarcloud`, `codecov`, `renovate`, custom org bots, …). A finding counts no matter who left it.
- When `merge:` shows `BEHIND` or `DIRTY`, rebase on the default branch.
- A CodeRabbit rate limit shows its ready time; relaunch `pr-watch`, which wakes when it lifts, then run `pr-threads comment '@coderabbitai review'`.
- Loop `pr-watch` → verify → group → fix → single push per batch → relaunch `pr-watch`, until no outstanding comment needs action, all CI checks pass green, and all required approvals are secured (by a human or by whichever bot gates the repo).
- When `pr-watch` reports the PR merged or closed, stop at once, even with checks or approvals outstanding, and report that terminal state.

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
- `pr-threads list` gives each unresolved thread's ID; answer with `pr-threads reply THREAD_ID -` and the body on stdin.
- Only a review's top-level summary body, which has no file or line, has no thread to answer in. That one, and only that one, gets `pr-threads comment`.
- Leave every thread open after replying: the reviewer who raised it, or another human, decides when it is settled. `pr-threads resolve` runs only when the user asks for it.

## Comment Formatting & Media
- Format comments posted on the maintainer's behalf as follows:
  `<!-- model: <slug> --> responding on behalf of <User>\n\n<reply>`.
- Embed screenshots or uploaded media links when visual evidence helps clarify the fix.

## Scope Constraint
- **Do not allow review feedback to expand the PR beyond the original goal.** Address genuine issues, but strictly prevent scope creep.
