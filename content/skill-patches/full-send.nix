# Drops the unshipped `sol-loop` step and renumbers the rest; swaps the "full send" phrase for "ship it".
[
  {
    from = "description: Trigger this if the user says 'full send'.";
    to = "description: Trigger this if the user says 'ship it', asking you to take the work to a merged PR on your own.";
  }
  {
    from = "# Full Send";
    to = "# Ship It";
  }
  {
    from = ''request "full send" in'';
    to = ''request "ship it" in'';
  }
  {
    from = ''A "full send" request is'';
    to = ''A "ship it" request is'';
  }
  {
    from = "3. **Get feedback.** Use the `sol-loop` skill to verify changes.\n4. **File the PR**";
    to = "3. **File the PR**";
  }
  {
    from = "5. **Babysit the PR**";
    to = "4. **Babysit the PR**";
  }
  {
    from = "6. **Merge** when";
    to = "5. **Merge** when";
  }
  {
    from = "7. **Report** in";
    to = "6. **Report** in";
  }
  {
    from = "Stay active from step 1 to step 7.";
    to = "Stay active from step 1 to step 6.";
  }
]
