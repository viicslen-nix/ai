{
  projectRootFile = "flake.nix";
  programs = {
    deadnix.enable = true;
    statix.enable = true;
    alejandra.enable = true;
    shfmt = {
      enable = true;
      indent_size = 2;
    };
  };
  settings = {
    # Lower runs first: the linters rewrite code, so alejandra must format after them.
    formatter = {
      deadnix.priority = 1;
      statix.priority = 2;
      alejandra.priority = 3;
    };
    # Vendored by `gh skill install`; `just update-skills` overwrites any local edit.
    global.excludes = [
      "content/skills/**"
      "content/integrations/skills/**"
    ];
  };
}
