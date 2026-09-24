# Anchor `from` on plain ASCII spans that survive an upstream reword.
[
  {
    from = "In everything the human reads (narration, the map's Decisions-so-far)";
    to = "In everything the human reads (narration, briefings and questions, the map's Decisions-so-far)";
  }
  {
    from = "<the decision or investigation this ticket resolves>";
    to = ''
      <the decision or investigation this ticket resolves, in one sentence>

      ## Why now

      <the closed ticket or map note that raised this, by name; what is blocked on it>

      ## What it changes

      <per likely answer: the concrete consequence (files, systems, data, workflow touched; what it rules in or out)>

      ## Unblocks

      <tickets and Not-yet-specified patches this opens up, by name>'';
  }
  {
    from = "Each ticket carries a `wayfinder:<type>` label, one of";
    to = ''
      Fill every section when the ticket is created, while the reasoning is fresh: a later session sees only the map's one-line gists and this body, and must be able to explain the stakes from them alone. **What it changes** states consequences, not a restatement of the question; if you can't name any, the ticket is still fog.

      Each ticket carries a `wayfinder:<type>` label, one of'';
  }
  {
    from = ''If in doubt, call the Skill tool twice, for "grilling" and "domain-modeling".'';
    to = ''If in doubt, call the Skill tool twice, for "grilling" and "domain-modeling". **Brief before the first question** of a HITL ticket: a short prose orientation giving the destination, this ticket and why it exists now, the decisions so far that bear on it, what each likely answer would change, and what resolving it unblocks. A question asked cold, without this, leaves the human guessing what they are deciding.'';
  }
]
