---
description: Answer a question about the code without changing anything.
disable-model-invocation: true
argument-hint: The question to answer.
agent: ask
disallowed-tools: Edit, Write, NotebookEdit
---

Answer the following — **do not create, edit, or delete any files in the project**, including through shell commands (no redirects into it, `sed -i`, `git commit`, `git checkout`, installs, or formatters).

**$ARGUMENTS**

Read whatever code or context you need. Shell commands are fine for investigating: searching, running read-only tools, querying, or reproducing behaviour. Scratch files may go in a temporary directory outside the project (the harness's temp dir, else `$TMPDIR` or `/tmp`), never inside it. Reply with a clear, concise answer, citing `file:line` where relevant. If answering properly would need a change, describe it instead of making it.

If `$ARGUMENTS` is empty, ask what I want to know before proceeding.
