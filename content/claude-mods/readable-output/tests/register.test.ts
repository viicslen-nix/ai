import type { On, RenderInput } from 'claude-code'
import { describe, expect, test } from 'claude-code/testing'

function textOf(tree: unknown): string {
  if (typeof tree === 'string' || typeof tree === 'number') return String(tree)
  if (Array.isArray(tree)) return tree.map(textOf).join('')
  if (!tree || typeof tree !== 'object') return ''
  return textOf((tree as { children?: unknown }).children)
}

const call = (tool: string, input: Record<string, unknown>) => ({
  tool_use_id: `toolu_${tool}`,
  tool,
  input,
  isRunning: false,
  isErrored: false,
  isInterrupted: false,
})

const BASH = {
  surface: 'terminal',
  component: 'ToolUse',
  requestId: 'toolu_Bash',
  props: { ...call('Bash', { command: 'ls -la\necho more', description: 'List files' }) },
} as unknown as RenderInput<'ToolUse'>

const GROUP = {
  surface: 'terminal',
  component: 'ToolGroup',
  requestId: 'collapsed-1',
  props: {
    calls: [call('Bash', { command: 'ls' }), call('Read', { file_path: '/x/README.md' }), call('Bash', { command: 'pwd' })],
    isActive: false,
    isExpanded: false,
  },
} as unknown as RenderInput<'ToolGroup'>

const PROMPT = {
  surface: 'terminal',
  component: 'UserMessage',
  requestId: 'm1',
  props: { text: 'hello there', origin: { kind: 'composer' }, isExpanded: false },
} as unknown as RenderInput<'UserMessage'>

const ENGINE = { type: 'engine', ref: 0 } as const
const engineBelow = (on: On) => on('ui.render', () => ENGINE)

describe('readable-output', () => {
  test('a tool row names the tool and the first line of its command', async $ => {
    const text = textOf(await $.ui.render(BASH))
    expect(text).toContain('Bash')
    expect(text).toContain('ls -la')
    expect(text).toContain('List files')
    expect(text).not.toContain('echo more')
  })

  test('a collapsed group counts its calls per tool and shows the last one', async $ => {
    const text = textOf(await $.ui.render(GROUP))
    expect(text).toContain('Bash ×2')
    expect(text).toContain('Read')
    expect(text).toContain('pwd')
  })

  test('an expanded group is left to the engine', async ($, on) => {
    engineBelow(on)
    const tree = await $.ui.render({ ...GROUP, props: { ...GROUP.props, isExpanded: true } } as typeof GROUP)
    expect(tree).toEqual(ENGINE)
  })

  test('a prompt from the composer is drawn on a band, any other message is left alone', async ($, on) => {
    engineBelow(on)
    expect(textOf(await $.ui.render(PROMPT))).toContain('hello there')
    const queued = { ...PROMPT, props: { ...PROMPT.props, origin: { kind: 'task-notification' } } } as unknown as typeof PROMPT
    expect(await $.ui.render(queued)).toEqual(ENGINE)
  })

  test('remote surfaces are left to the engine', async ($, on) => {
    engineBelow(on)
    expect(await $.ui.render({ ...BASH, surface: 'desktop' } as unknown as typeof BASH)).toEqual(ENGINE)
  })
})
