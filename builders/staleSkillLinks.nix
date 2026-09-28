# A skill that was a file and is now a directory leaves home-manager's old
# `skills/<name>` link behind, and linkGeneration cannot mkdir through it.
{lib}: dir:
lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] ''
  for link in "${dir}"/*; do
    if [[ -L $link && ! -d $link && $(readlink "$link") == /nix/store/*-home-manager-files/* ]]; then
      run rm $VERBOSE_ARG "$link"
    fi
  done
''
