// Narration: an assistant text block the model followed with a tool call before the next prompt.

export type Message = { role: 'user' | 'assistant'; text: string; toolUses: unknown[]; toolResults?: unknown[] }
type Chunk = { kind: string; index?: number; text?: string }
export type Step = { blocks: Map<number, string>; waiters: Array<(tool: boolean) => void> }

const KNOWN_MAX = 200
const known = new Set<string>()
const active = new Set<Step>()

function remember(text: string) {
  const trimmed = text.trim()
  if (!trimmed) return
  known.add(trimmed)
  if (known.size > KNOWN_MAX) known.delete(known.values().next().value as string)
}

function settle(s: Step, tool: boolean) {
  for (const waiter of s.waiters.splice(0)) waiter(tool)
}

export function openStep(): Step {
  const s: Step = { blocks: new Map(), waiters: [] }
  active.add(s)
  return s
}

export function observe(s: Step, chunk: Chunk) {
  if (chunk.kind === 'text' && chunk.index !== undefined) {
    s.blocks.set(chunk.index, (s.blocks.get(chunk.index) ?? '') + (chunk.text ?? ''))
  }
  if (chunk.kind === 'tool') for (const text of s.blocks.values()) remember(text)
  // Block starts and ends arrive as 'engine' chunks between a text block and the tool call after it.
  if (chunk.kind === 'text' || chunk.kind === 'tool' || chunk.kind === 'stop') settle(s, chunk.kind === 'tool')
}

export function closeStep(s: Step) {
  settle(s, false)
  active.delete(s)
}

export function isKnown(needle: string): boolean {
  for (const k of known) if (k.includes(needle)) return true
  return false
}

// The verdict on a block of the step still streaming: settles on its next chunk.
export function pending(needle: string): Promise<boolean> | undefined {
  for (const s of active) {
    if ([...s.blocks.values()].some(block => block.includes(needle))) {
      return new Promise(resolve => s.waiters.push(resolve))
    }
  }
  return undefined
}

export function followedByTool(list: ReadonlyArray<Message>, needle: string): boolean {
  const at = list.findLastIndex(m => m.role === 'assistant' && m.text.includes(needle))
  if (at < 0) return false
  for (const m of list.slice(at)) {
    if (m.role === 'assistant' && m.toolUses.length > 0) return true
    if (m.role === 'user' && !m.toolResults?.length) return false
  }
  return false
}
