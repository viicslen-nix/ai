# The oh-my-opencode variant: the same opencode v1 module, plus the plugin and
# the model each of its agents runs on.
_: {
  programs.opencode1.settings.plugin = ["oh-my-opencode@latest"];

  xdg.configFile."opencode1/oh-my-opencode.json".text = builtins.toJSON {
    agents = {
      sisyphus = {model = "google/gemini-claude-opus-4-5-thinking";};
      oracle = {model = "google/gemini-3-pro-preview";};
      "multimodal-looker" = {model = "google/gemini-3-flash";};
      explore = {model = "google/gemini-3-flash";};
      librarian = {model = "google/gemini-3-pro-preview";};
    };
  };
}
