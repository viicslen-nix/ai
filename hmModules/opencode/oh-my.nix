# The oh-my-opencode variant: the same opencode module, plus the plugin and the
# model each of its agents runs on.
_: {
  programs.opencode.settings.plugin = ["oh-my-opencode@latest"];

  xdg.configFile."opencode/oh-my-opencode.json".text = builtins.toJSON {
    agents = {
      sisyphus = {model = "google/gemini-claude-opus-4-5-thinking";};
      oracle = {model = "google/gemini-3-pro-preview";};
      "multimodal-looker" = {model = "google/gemini-3-flash";};
      explore = {model = "google/gemini-3-flash";};
      librarian = {model = "google/gemini-3-pro-preview";};
    };
  };
}
