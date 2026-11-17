import { apiKey, config, DEFAULT_CONTEXT, DEFAULT_OUTPUT, discover, providerFor } from "./discover.mjs";

// Shaped like opencode's own variants for each SDK.
const effortSettings = {
  anthropic: (effort) =>
    effort === "none"
      ? { thinking: { type: "disabled" } }
      : { thinking: { type: "adaptive", display: "summarized" }, effort },
  openai: (effort) => ({
    reasoningEffort: effort,
    reasoningSummary: "auto",
    include: ["reasoning.encrypted_content"],
  }),
  gemini: (effort) => ({ thinkingConfig: { includeThoughts: true, thinkingLevel: effort } }),
};

export default {
  id: `${config.name}-models`,
  async setup(ctx) {
    if (!ctx.provider) return;
    const groups = await discover();
    const key = apiKey();
    await ctx.provider.transform((editor) => {
      for (const [group, { api, models }] of Object.entries(groups)) {
        const { id, name, package: pkg, baseURL } = providerFor(config.opencode, group, api);
        editor.add({
          info: { id, name, activation: "enabled", package: pkg, settings: { baseURL, apiKey: key } },
          models: models.map((m) => ({
            id: m.id,
            modelID: m.id,
            providerID: id,
            name: m.name,
            capabilities: { tools: true, input: m.image ? ["text", "image"] : ["text"], output: ["text"] },
            variants: m.efforts.map((effort) => ({ id: effort, settings: effortSettings[api](effort) })),
            time: { released: 0 },
            cost: [],
            status: "active",
            enabled: true,
            limit: { context: m.contextWindow ?? DEFAULT_CONTEXT, output: m.maxOutput ?? DEFAULT_OUTPUT },
          })),
        });
      }
    });
  },
};
