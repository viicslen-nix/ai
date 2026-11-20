---
name: deglue
description: After a migration or rewrite, find and remove the leftover glue (pass-through wrappers), stringly-typed values that should be enums, and duplicated code, in any repo.
argument-hint: "[paths | ref | range | PR# | branch]... [--report-only]"
disable-model-invocation: true
---

# Deglue

A migration lands in two moves: build the new core, then **glue** it to the old callers so nothing breaks. This skill does the third move people skip: take the glue back out. It also sweeps for the two other things migrations leave behind: **stringly-typed** values, where an old SDK's constants became raw strings, and **twins**, where old and new copies of the same logic both survived.

The definitions, signals, keep rules and fix shapes for each category are in [`REFERENCE.md`](REFERENCE.md). Every detector reads it.

## 1. Resolve the scope

Arguments are combined into one scope. Each one is:

| Argument | Files in scope |
| --- | --- |
| path or glob | those files |
| `PR#` or branch | `git diff --name-only $(git merge-base <default> <head>)...<head>` |
| ref (`origin/main`) | everything changed since that ref's merge-base with `HEAD` |
| range (`a..b`) | `git diff --name-only a..b` |
| none | the current branch against the default branch's merge-base. Confirm it with the user before going on |

Passing several changes at once (two PRs, or one branch that carries both) gives one scope. Tag every file with the change that touched it so the report can be split later.

Then find the **new core**: what the change brought in. That means new dependencies (`composer.json`, `package.json`, `go.mod`, …), new submodules or packages, and namespaces newly imported across the diff. Glue sits where old callers meet the new core. Grow the scope by one hop: add every file that calls into the new core or into a class the diff changed, even files the diff itself didn't touch. That catches old wrappers that now only forward to the new code.

**Done when** you have a list of files in scope, each tagged with its change, and a named new core.

## 2. Load the house rules

Read the repo's agent instructions (`AGENTS.md`, `CLAUDE.md`, rule indexes) and every rule file that covers a path in scope. Note the conventions that change a verdict, such as "actions may be invoked as jobs", "enums live in X", "no API resources" or "tests use `it()`". Pass them to the detectors as a short list.

## 3. Detect

Split the in-scope files into areas of about 60 files each, by directory or module. Launch one read-only subagent per area, all in one message. Brief each one with:
- its file list, the new core, and the house-rule list;
- read [`REFERENCE.md`](REFERENCE.md) (give its absolute path);
- check every file for all three categories, and grep the whole repo for **twins** of anything it finds, not just its own area;
- return rows only: `file:line | category | what it forwards to / literal / twin location | caller count (grep, measured) | introduced by (commit via git log -S) | proposed verdict + reason`.

**Done when** every file in scope is covered by some detector's report.

## 4. Verify

Merge the rows and collapse twins reported by more than one detector. Check every candidate against the current code yourself:
- Grep every caller, including string references: container bindings, route files, queue payloads, config, morph maps and frontend calls. A caller count must come from a search you ran.
- Apply the keep rules in `REFERENCE.md`. A row that hits one is reported as **keep (reason)**, not dropped silently.
- For stringly-typed values that are persisted, query the distinct stored values, or say the check wasn't possible. An enum swap that misses a stored value is a runtime failure.
- Anything inside a vendored package or a submodule that other repos use is **report-only**.

**Done when** every candidate has a verdict (remove, inline, enum, merge, keep or report-only) and a measured caller count.

## 5. Report and choose

Show one table grouped by change, then by category. Columns: location, finding, callers, verdict, fix, risk. If there are more than about 25 rows, also offer an HTML page. Ask the user which groups to apply, using AskUserQuestion with multi-select. With `--report-only`, stop here.

## 6. Apply

Work on your own branch, stacked on the scope's head. If another session is working on that head, check before touching its worktree. Fix one category per area per commit:
- **Glue:** point every caller at the target, then delete the wrapper. Keep any validation and error handling it did by moving it into the caller or the target. Move its tests onto the target: fake the dependency instead of mocking the wrapper.
- **Stringly-typed:** type the parameters, properties and casts with the enum. Convert at the trust boundary (request validation, model cast, payload parsing). Call `->value` (or the language's equivalent) only at a boundary that requires a string.
- **Twins:** keep the newer or better-tested copy as the single source of truth, then delete the other one and redirect its callers.

After each commit, run the affected tests, the formatter and static analysis on the touched files. Grep for the deleted symbol and expect zero hits.

**Done when** every chosen row is applied with its tests passing, or reported back with the reason it couldn't be.

## 7. Hand back

One line per commit. Then list the report-only rows (submodules, external contracts) that are still open, the checks you skipped, and any stored value an enum might not cover.
