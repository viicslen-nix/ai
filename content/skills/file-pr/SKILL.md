---
description: use when the user asks to file, open, or create a PR
---

# File PR Skill

## Pre-Filing Checks
- Read the repo instructions and inspect `git status` first.
- Commit outstanding changes exactly like the standalone `commit` command: separate them into logical groups and commit each.
- Review the diff locally against `origin/<base>`, where `<base>` is the repo default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`), to verify its contents match the original goal.
- Push the current branch.
- Check whether a pull request for this branch already exists. If one does, reuse it — update its title and body instead of opening another.

## PR Creation & Workflow
- Prefer `gh` for PR discovery and creation. Pass the body with `--body-file` so code fences and Mermaid survive shell quoting.
- **Do not open draft pull requests.** Open real PRs so automated review bots are triggered.
- If the user also requests to monitor or watch the pull request, continue directly with the **babysit-pr** skill.

## Title Conventions
- Use conventional commit style: `type(scope): subject` (`!` after the scope for breaking changes).
- Write concise, human-readable titles that explain **why** the changes matter, following repository conventions.
- **Bad Title Example:** `feat(server): negotiate per message deflate on the websocket`.
- **Good Title Example:** `perf(server): cut websocket frame size by 70% with gzipping`.

## Body Template

```markdown
<one or two sentences: the problem, in the user's terms, then the fix>

## Summary

<diagram, diff-sketch, or tree>

## Evidence

<before / after>

## Merge Danger

**Door:** <one-way or two-way> — <optional: why>
**Blast Radius:** <one or two words> — <optional: what could break, for whom>

## Deployment / ## Runbook / ## Merge Checklist   (only when they apply)

---
<AI model and harness used to make the changes>
```

Skip preambles and keep prose brief. Use the repo's domain language — its `GLOSSARY.md` when one exists. Omit a section entirely when nothing belongs in it; never write "N/A". Summary, Evidence and Merge Danger are always present.

### Opening lines
- State the core problem as the user experienced it, then the fix in one sentence.
- **Do not lead with an implementation inventory** or a list of file changes.
  - **Bad:** `removed implicit workspace carryover from every new thread entry point...`.
  - **Good:** `my new work tree default was ignored when starting new threads on existing work trees...`.

### Summary
Show the change with the **smallest view that makes the key point clear**. Usually one, sometimes two; never all of them. Put each view next to the one line of text it supports, and keep only the calls, files, props, states and boundaries the reviewer needs.

| The point is… | Show it as |
| --- | --- |
| logic or an algorithm | pseudocode |
| runtime control flow | a call tree |
| UI structure | a component tree, with state and module boundaries that matter |
| file responsibility or a broad refactor | a shallow file tree with one-line `#` notes |
| interaction or data flow between parts | a Mermaid `sequenceDiagram` / `flowchart` |
| what changes in a shape that already exists | a `diff` block of that tree or pseudocode (`+`/`-` lines) |
| a mostly-new block the reviewer needs to see whole | the full code block |

A diff-sketch is usually the strongest choice for a modification. Match it to the topic, e.g. a call-tree change:

```diff
 submitForm
   createSession
     persistPrompt
+    expandSkillMention
     launchAgent
```

### Evidence
Concrete before/after proof that the change works. Pick the best tier the environment allows:

- **S-tier — screenshots**, whenever the change is visible (UI, layout, styling, copy, rendered output).
  - Capture "before" from the base branch (a worktree at `origin/<base>`) and "after" from this branch, at the same viewport, data and state. Pair them in a table with `Before` / `After` columns, cropped to what changed; add a full-page shot only when placement matters.
  - The table holds real images only. Never fill a cell with a description of what a screenshot would show. If one side cannot be captured, leave it out; if neither can, drop the table and say why in one sentence.
  - For a multi-step flow or an interaction a still cannot show (animation, drag and drop, transitions, loading states), add a short trimmed GIF of the "after" flow when it communicates something the stills do not.
  - `gh` cannot upload attachments. Host images with `scripts/pr-asset FILE...` (beside this file): it commits them to the orphan `assets/pr-screenshots` branch without a checkout and prints the `https://github.com/<owner>/<repo>/raw/assets/pr-screenshots/<file>` URL to embed. Name files `<topic>-before.png` / `<topic>-after.png`; a same-named file is overwritten. If the push fails, tell the user which files to drag into the description.
- **A-tier — execution**: the exact test that failed before and passes now (named, with its assertion as pseudocode), or the command output before and after. Run it on both sides; don't claim a "before" you did not observe.

  ```markdown
  - **Before:** `saves twice → returns cached result` ✗ (wrote file twice)
    **After:** ✓
  ```

- Below that, say plainly what was verified and how (typecheck, manual check) and what was not.

### Merge Danger
- **Door:** a **two-way door** is cheap to walk back (revert the commit, flip a flag). A **one-way door** is not: destructive migrations, data deletion or rewrites, published API/schema changes consumers adopt, sent emails or webhooks, irreversible infra. Say which, and why if it isn't obvious.
- **Blast Radius:** who and what is affected if it's wrong — one or two words (e.g. `internal-only`, `checkout`, `all tenants`), then the plausible failure modes: layout shift, mobile breakage, broken consumers, performance, permissions, cost. Consider all of them; list only the real ones.

## Deployment & Runbook Sections
Tell whoever merges and ships the PR what they have to *do*, not just what changed. Read the diff for anything that does not take effect by deploying the code alone: migrations, backfills, artisan/rake/manage commands, cache or search-index rebuilds, feature flags, new env vars or secrets, config changes, new infrastructure (queues, buckets, topics, tables, DNS, IAM), cron or worker changes, and dependency order between services or repos. These items are usually what makes a door one-way — keep Merge Danger consistent with them.

- **`## Deployment`** — infrastructure and configuration that must exist before or alongside the deploy, e.g. "create the `orders-export` SQS queue and grant the worker role `sqs:SendMessage` before deploying", new env vars with where their values come from, or "deploy `api` before `web`".
- **`## Runbook`** — commands that must be run by hand after deployment, as copy-pasteable code blocks with the environment they run in, whether they are idempotent, how to verify they worked, and how to roll them back.
- **`## Merge Checklist`** — ordered steps grouped by phase:
  - **Before merging** — prerequisites such as provisioning, secrets, a dependent PR landing first, or a heads-up to another team.
  - **While merging** — anything time-sensitive during merge/deploy, such as merge order, a maintenance window, pausing workers, or toggling a flag.
  - **After merging** — the runbook commands, smoke checks, what to monitor, and follow-up cleanup (removing a flag, dropping an old column).
- Only include phases that have real steps. A PR that ships with a plain deploy needs none of these sections.
- When unsure whether something needs a manual step, state the assumption in the section rather than leaving it out.
