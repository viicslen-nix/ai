# Anchor `from` on plain ASCII spans that survive an upstream reword.
[
  {
    from = "Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.";
    to = ''
      Ask the whole frontier in one round, through the harness's interactive question tool where one exists (in Claude Code: `AskUserQuestion`), rather than as prose the user has to answer by hand. That tool takes a bounded number of questions per call and each call blocks until answered, so a wide frontier is simply several calls back to back — never a reason to hold part of the frontier back for a later round.

      Per question: a short `header`; a `question` that gives the situation, the decision, and why it matters in one to three sentences, enough for someone who wasn't following along to answer it; and 2-4 concrete `options`. Your recommended answer goes **first**, with `(Recommended)` appended to its label, and each option's `description` names the concrete consequence of picking it (what changes, what it rules out), not a restatement of its label. When a question needs more background than the tool holds, write that background as prose immediately before the call, not instead of it. Use `multiSelect` when the choices genuinely compose rather than exclude. An open-ended decision still belongs in the tool: enumerate the answers you would expect, and let the user's free-text "Other" override you.

      Then wait for the user's answers before the next round.'';
  }
  {
    from = "Format a round like so:";
    to = "Where no such tool exists, fall back to asking in prose, formatted like so:";
  }
]
