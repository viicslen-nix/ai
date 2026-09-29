---
description: use when the user asks to file, open, or create a PR
---

# File PR Skill

## Pre-Filing Checks
- Read the repo instructions and inspect `git status` first.
- Commit outstanding changes exactly like the standalone `commit` command: separate them into logical groups and commit each.
- Review the diff locally against `origin/main` to verify its contents match the original goal.
- Push the current branch.
- Check whether a pull request for this branch already exists. If one does, reuse it — update its title and body instead of opening another.

## PR Creation & Workflow
- Prefer `gh` for PR discovery and creation.
- **Do not open draft pull requests.** Open real PRs so automated review bots are triggered.
- If the user also requests to monitor or watch the pull request, continue directly with the **babysit-pr** skill.

## Title Conventions
- Write concise, human-readable titles that explain **why** the changes matter, following repository conventions.
- **Bad Title Example:** `PF server negotiate per message deflate on the websocket`.
- **Good Title Example:** `PF server cut websocket frame size by 70% with gzipping`.

## Description Formatting
- Open the description with a simple explanation of the core problem based on the user's prompt, followed by a brief overview of the solution.
- **Do not lead with an implementation inventory** or a list of file changes.
  - **Bad Description Example:** `removed implicit workspace carryover from every new thread entry point...`.
  - **Good Description Example:** `my new work tree default was ignored when starting new threads on existing work trees...`.
- Follow the summary with the operational sections below whenever they apply. Omit a section entirely when nothing belongs in it — no "N/A" placeholders.
- Include a blurb at the end of the PR description specifying the AI model and harness used to make the changes.

## Visual Evidence
When the change affects anything a user sees — UI, layout, styling, copy, rendered output — add a `## Screenshots` section with **before and after** images of each affected view.

- Capture "before" from the base branch (e.g. a worktree at `origin/main`) and "after" from this branch, at the same viewport, data, and state so the two are directly comparable. Pair them side by side in a table with `Before` / `After` columns.
- Use whatever browser or screenshot tooling is available. If the app cannot be run locally, say so in the section instead of omitting it silently.
- Crop to the part that changed; add a full-page shot only when placement or context matters.
- When the change is a multi-step flow or an interaction a still cannot show (animations, drag and drop, transitions, loading states), also record a short video or GIF of the "after" flow — at your discretion, and only when it communicates something the screenshots do not. Keep it short and trimmed to the flow.
- `gh` cannot upload attachments to a PR. Commit the assets to a dedicated branch (not the PR branch) and embed them by URL, e.g. `https://github.com/<owner>/<repo>/raw/<assets-branch>/<file>`. GIFs render inline; a video linked this way shows as a link, so prefer a GIF for short flows. If none of this works, tell the user which files to drag into the PR description.
- Skip the section for changes with no visual effect.

## Deployment & Runbook Sections
The description must tell whoever merges and ships the PR what they have to *do*, not just what changed. Read the diff for anything that does not take effect by deploying the code alone: migrations, backfills, artisan/rake/manage commands, cache or search-index rebuilds, feature flags, new env vars or secrets, config changes, new infrastructure (queues, buckets, topics, tables, DNS, IAM), cron or worker changes, and dependency order between services or repos.

- **`## Deployment`** — infrastructure and configuration that must exist before or alongside the deploy, e.g. "create the `orders-export` SQS queue and grant the worker role `sqs:SendMessage` before deploying", new env vars with where their values come from, or "deploy `api` before `web`".
- **`## Runbook`** — commands that must be run by hand after deployment, as copy-pasteable code blocks with the environment they run in, whether they are idempotent, how to verify they worked, and how to roll them back.
- **`## Merge Checklist`** — ordered steps grouped by phase:
  - **Before merging** — prerequisites such as provisioning, secrets, a dependent PR landing first, or a heads-up to another team.
  - **While merging** — anything time-sensitive during merge/deploy, such as merge order, a maintenance window, pausing workers, or toggling a flag.
  - **After merging** — the runbook commands, smoke checks, what to monitor, and follow-up cleanup (removing a flag, dropping an old column).
- Only include phases that have real steps. A PR that ships with a plain deploy needs none of these sections.
- When unsure whether something needs a manual step, state the assumption in the section rather than leaving it out.
