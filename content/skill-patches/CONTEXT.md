# CONTEXT

Local deltas applied to upstream skills by `patchSkill`, one file per skill.
Each is a list of `{from; to;}` spans rewritten into the upstream `SKILL.md`.

## grilling.nix

A local delta on `github:mattpocock/skills` — `skills/productivity/grilling`.

Upstream has the agent print numbered questions as prose and wait for the user
to type answers back. Every harness we run it in has an interactive question
tool instead, so the round goes through that and the prose block is kept as the
documented fallback. The tool's terse fields invite context-free questions, so
the patch requires each question and option to carry its stakes.

## implement.nix

A local delta on `github:mattpocock/skills` — the `implement` skill.

Upstream ends every task with a run of the full test suite. Here that suite is
too slow to run once per task, and CI runs it on every push anyway, so the
patch keeps the regular typechecks and single-file test runs and drops the
end-of-task full run.

## wayfinder.nix

A local delta on `github:mattpocock/skills` — `skills/engineering/wayfinder`.

Upstream tickets hold only the question, so a later session resolving one can't
say why it matters or what an answer changes. The patch adds Why now / What it
changes / Unblocks sections to the ticket body and a prose briefing before the
first question of a HITL ticket.

The `from` anchors are plain ASCII spans that have survived every upstream
reword so far. `patchSkill` asserts they still exist, so a reword breaks the
build rather than silently reverting grilling to vanilla. Paragraphs in `to`
are single unwrapped lines, to match the surrounding upstream prose.

## full-stop.nix

A local delta on `github:t3dotgg/tstack` — `skills/full-stop`.

Upstream triggers on the phrase "full stop", even a closing "Full stop." used
for emphasis. Here "full stop" means stop all work at once, so the patch strips
every trigger phrase and `skillRenames` installs the skill as
`merge-ready`. `patchSkill` returns only `SKILL.md`, which drops the
upstream `agents/openai.yaml` (Codex display metadata that still names
`$full-stop`).

## full-send.nix

A local delta on `github:t3dotgg/tstack` — `skills/full-send`.

Upstream asks for a `sol-loop` feedback step this setup does not ship; the
patch drops it and renumbers the steps. "Full send" also read as childish, so
the trigger phrase becomes "ship it" and `skillRenames` installs the skill as
`ship-it`; `full-stop.nix` swaps its own mentions of full-send to match.

## council.nix

A local delta on `github:t3dotgg/tstack` — `skills/council`.

Upstream names "Gemini Pro" only as an example, so the agent grabbed whatever
Gemini model T3 listed first — including Gemini 4 Argon, which appears under
the Claude provider and isn't a real Gemini account model. The patch pins the
Gemini member to the Antigravity provider and has it pick the strongest Gemini
model that account offers (Pro over Flash, newest first), so the choice follows
the account instead of a hard-coded id.
