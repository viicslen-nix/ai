def leaves: [paths(type != "object") | select(all(.[]; type == "string"))];
def at($p): try getpath($p) catch null;

# A value still equal to what the last activation wrote was never touched at runtime.
def prune($old; $new):
  reduce ($old | leaves[]) as $p (.;
    if ($new | at($p)) == null and at($p) == ($old | at($p)) then delpaths([$p]) else . end);

def seed($old; $new):
  reduce ($new | leaves[]) as $p (.;
    . as $s
    | at($p) as $cur
    | if $cur == null or $cur == ($old | at($p))
      then (try setpath($p; $new | getpath($p)) catch $s)
      else .
      end);

($oldDefaults[0] // {}) as $oldD
| ($oldEnforced[0] // {}) as $oldE
| $newDefaults[0] as $newD
| $newEnforced[0] as $newE
| $current
| prune($oldD; $newD)
| prune($oldE; $newE)
| seed($oldD; $newD)
| . * $newE
