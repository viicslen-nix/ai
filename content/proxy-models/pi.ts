import { config, DEFAULT_CONTEXT, DEFAULT_OUTPUT, discover, providerFor } from "./discover.mjs";

export default async function (pi: any) {
  const groups = await discover();
  for (const [group, { api, models }] of Object.entries(groups) as [string, { api: string; models: any[] }][]) {
    const { id, ...provider } = providerFor(config.pi, group, api);
    pi.registerProvider(id, {
      ...provider,
      models: models.map((m) => ({
        id: m.id,
        name: m.name,
        reasoning: m.efforts.length > 0,
        input: m.image ? ["text", "image"] : ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: m.contextWindow ?? DEFAULT_CONTEXT,
        maxTokens: m.maxOutput ?? DEFAULT_OUTPUT,
      })),
    });
  }
}
