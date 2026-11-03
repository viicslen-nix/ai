# Strips every "full stop" trigger phrase and the "full send" prose; installed as `merge-ready`.
[
  {
    from = ''description: Trigger this if the user says 'full stop', even as a closing "Full stop." that reads like emphasis.'';
    to = "description: Use when the user asks for ship-it's end-to-end PR work but wants to merge the PR themselves.";
  }
  {
    from = "# Full Stop";
    to = "# Merge Ready";
  }
  {
    from = ''An explicit "full stop" request'';
    to = "An explicit request for this skill";
  }
  {
    from = ''A "full stop" request is'';
    to = "A request for this skill is";
  }
  {
    from = ''a separate "full send" request'';
    to = ''a separate "ship it" request'';
  }
  {
    from = "[full-send](";
    to = "[ship-it](";
  }
  {
    from = "full-send's";
    to = "ship-it's";
  }
]
