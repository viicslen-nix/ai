---
name: full-push
description: Trigger this if the user says 'full push'. Commits every change in the repo and its submodules, including ones made outside this session, updates submodule pointers, and pushes everything.
---

# Full Push

Commit and push the whole working tree of the current repository and every submodule under it, whoever made the changes. If the user did not clearly ask for a full push, commit only this session's changes instead.

## Order

Work deepest submodule first, the root repository last: a parent can only record a submodule's pointer once that submodule's commits exist on its remote. List the submodules with `git submodule status --recursive`.

For each repository, deepest first:

1. **Inspect** with `git status` and `git diff`, untracked files included. Read what you are about to commit; most of it you did not write.
2. **Get on a branch.** Commit to `main` or `master` when on it, otherwise to the current branch. A submodule on a detached HEAD: if HEAD equals the tip of the remote default branch, check that branch out and carry on; otherwise stop and ask, since commits on a detached HEAD have nowhere to be pushed.
3. **Commit** in logical groups as the **commit** skill does, with conventional commit messages. Path-scope each commit (`git commit -- <paths>`) so groups do not bleed into each other.
4. **Stage changed submodule pointers** (`git add <submodule>`) in their own commit, `chore: bump <name>`, after the submodule itself has been pushed. Commit a pointer that moved even when nothing in the submodule changed in this run.
5. **Push** to the branch's upstream. If the push is rejected because the remote moved, `git pull --rebase` and push again; if the rebase conflicts, stop and ask. Push a repository that has unpushed commits even when its tree was already clean.

## Stop and ask

- A file looks like a secret or credential (`.env`, private keys, tokens, `*.pem` that is not a public cert), or like a build artifact or junk that `.gitignore` misses. Do not commit it to find out.
- A push still fails after one rebase, or a rule or hook rejects it.
- Anything would need a force-push. Never force-push.

## Report

One line per repository: the commits made, with short SHAs, and the branch pushed. Name anything left uncommitted and why.
