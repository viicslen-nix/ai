---
description: Loop council reviews on the current work, fixing between rounds, until every member approves.
disable-model-invocation: true
argument-hint: Optional focus, bar, or member changes (e.g. "make it robust", "skip Gemini").
---

Improve the work in this thread with the `council` skill, and **do not stop until every council member is satisfied**.

**$ARGUMENTS**

Treat the arguments as the focus, the quality bar, or changes to council membership (for example, dropping a member). If they are empty, review the current work against what I originally asked for in this thread.

Follow the `council` skill for choosing members, running delegates, scoring, and reporting. On top of it:

1. **Get it ready first.** Finish the work in progress, fix the issues you already know about, and run the relevant checks before round 1.
2. **Brief neutrally.** Describe what I asked for and what the code does, and point delegates at the diff and the files. Never include your own verdicts, trade-off reasoning, or "deliberate shortcut" framing. A brief that defends a choice gets the choice approved instead of reviewed. Ask each member to judge whether the approach itself is right, not only whether it is implemented well.
3. **Define satisfied.** Each member gives a score out of 10, an explicit `APPROVE` or `CHANGES REQUESTED`, and a list of blocking issues. The council is satisfied only when every member returns `APPROVE` with no blocking issues in the **same** round. A high score with open blockers does not count. Neither does an approval that hinges on a shortcut, workaround, or "follow-up later".
4. **Loop without handing back.** After each round, fix every finding you agree with, re-run the checks, and start a fresh round with fresh delegates. Do not end your turn between rounds or ask me whether to continue.
5. **Disagree on the record.** If you think a finding is wrong or out of scope, do not silently skip it. Put your counter-argument, with evidence, in the next round's brief to that member and let them rule. If the same point is still deadlocked after that round, ask me with the question tool. That is the only reason to pause.
6. **Hold the scope.** Fixes serve my original request. Reject additions that grow scope, and say so in the next brief.

When the council is satisfied, reply with what changed across the rounds, the score table from the `council` skill, and anything still unchecked.
