// Nerd Font codicons (nf-cod-*), escaped so the source stays readable without the font.
export const GLYPH = {
  terminal: '\uea85',
  file: '\uea7b',
  edit: '\uea73',
  newFile: '\uea7f',
  search: '\uea6d',
  files: '\ueaf0',
  folder: '\uea83',
  globe: '\ueb01',
  telescope: '\ueb68',
  robot: '\ueb08',
  checklist: '\ueab3',
  book: '\ueaa4',
  notebook: '\uebaf',
  plug: '\ueb2d',
  question: '\ueb32',
  tools: '\ueb6d',
  ok: '\ueab2',
  error: '\uea87',
  interrupted: '\ueabd',
  running: '\ueb19',
  account: '\ueb99',
  sparkle: '\uec10',
  lightbulb: '\uea61',
  comment: '\uea6b',
  upload: '\ueac3',
  gear: '\ueaf8',
  watch: '\ueb7c',
} as const

// Muted mid-tones that read on light and dark themes alike (the theme's own
// keys are pastel, and a mod cannot tell which theme is on). Each channel is
// 0x48, 0x7e or 0xb0: chalk quantises v/51 linearly, so without truecolor
// these land on the cube's 5f, 87 and af instead of collapsing together.
export const PALETTE = {
  ink: '#dadada',
  claude: '#7e4848',
  user: '#487eb0',
  rail: '#444444',
  shell: '#7e487e',
  read: '#487e7e',
  write: '#7e48b0',
  web: '#7e7e48',
  plan: '#b07e48',
  skill: '#487e48',
  mcp: '#48487e',
  ask: '#b04848',
  other: '#6c6c6c',
  done: '#487e48',
  // Not muted: a skill call should catch the eye.
  loudSkill: '#00d787',
  loudInk: '#121212',
} as const

export type Style = { icon: string; color: string; label: string }

const SHELL = { icon: GLYPH.terminal, color: PALETTE.shell }
const READ = { color: PALETTE.read }
const WRITE = { color: PALETTE.write }
const WEB = { color: PALETTE.web }

const STYLES: Record<string, Omit<Style, 'label'> & { label?: string }> = {
  Bash: SHELL,
  BashOutput: { ...SHELL, label: 'Shell' },
  KillShell: { ...SHELL, label: 'Kill' },
  Read: { ...READ, icon: GLYPH.file },
  Grep: { ...READ, icon: GLYPH.search },
  Glob: { ...READ, icon: GLYPH.files },
  LS: { ...READ, icon: GLYPH.folder },
  Edit: { ...WRITE, icon: GLYPH.edit },
  MultiEdit: { ...WRITE, icon: GLYPH.edit },
  Write: { ...WRITE, icon: GLYPH.newFile },
  NotebookEdit: { ...WRITE, icon: GLYPH.notebook },
  WebFetch: { ...WEB, icon: GLYPH.globe, label: 'Fetch' },
  WebSearch: { ...WEB, icon: GLYPH.telescope, label: 'Search' },
  Task: { icon: GLYPH.robot, color: PALETTE.claude, label: 'Agent' },
  Agent: { icon: GLYPH.robot, color: PALETTE.claude },
  TodoWrite: { icon: GLYPH.checklist, color: PALETTE.plan, label: 'Todos' },
  ExitPlanMode: { icon: GLYPH.checklist, color: PALETTE.plan, label: 'Plan' },
  Skill: { icon: GLYPH.book, color: PALETTE.skill },
  AskUserQuestion: { icon: GLYPH.question, color: PALETTE.ask, label: 'Ask' },
}

const MCP = /^mcp__(.+?)__(.+)$/

export function styleOf(tool: string): Style {
  const mcp = MCP.exec(tool)
  if (mcp) return { icon: GLYPH.plug, color: PALETTE.mcp, label: mcp[1] ?? tool }
  const style = STYLES[tool]
  if (style) return { label: tool, ...style }
  return { icon: GLYPH.tools, color: PALETTE.other, label: tool }
}

export type Summary = {
  main: string
  detail?: string
  added?: number
  removed?: number
}

type Input = Record<string, unknown>

const str = (value: unknown): string => (typeof value === 'string' ? value : '')
const firstLine = (text: string) => text.split('\n', 1)[0] ?? ''
const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

export function relative(path: string, cwd: string): string {
  if (cwd && path.startsWith(cwd + '/')) return path.slice(cwd.length + 1)
  return path
}

function patchCounts(output: unknown): Pick<Summary, 'added' | 'removed'> {
  const hunks = (output as { structuredPatch?: { lines?: string[] }[] } | undefined)?.structuredPatch
  if (!Array.isArray(hunks)) return {}
  let added = 0
  let removed = 0
  for (const hunk of hunks) {
    for (const line of hunk.lines ?? []) {
      if (line.startsWith('+')) added += 1
      else if (line.startsWith('-')) removed += 1
    }
  }
  return { added, removed }
}

function compact(input: Input): string {
  const text = JSON.stringify(input)
  return text === '{}' ? '' : text
}

export function summaryOf(tool: string, raw: unknown, output: unknown, cwd: string): Summary {
  const input = (raw && typeof raw === 'object' ? raw : {}) as Input
  const path = relative(str(input.file_path) || str(input.notebook_path) || str(input.path), cwd)

  const mcp = MCP.exec(tool)
  if (mcp) return { main: mcp[2] ?? tool, detail: compact(input) }

  switch (tool) {
    case 'Bash':
      return { main: firstLine(str(input.command)), detail: str(input.description) }
    case 'Read': {
      const offset = Number(input.offset ?? 0)
      const limit = Number(input.limit ?? 0)
      const range = limit ? `L${offset || 1}-${(offset || 1) + limit - 1}` : str(input.pages)
      return { main: path, detail: range }
    }
    case 'Edit':
    case 'MultiEdit':
      return { main: path, detail: input.replace_all ? 'replace all' : '', ...patchCounts(output) }
    case 'Write':
      return { main: path, detail: plural(str(input.content).split('\n').length, 'line') }
    case 'NotebookEdit':
      return { main: path, detail: str(input.edit_mode) }
    case 'Grep': {
      const where = [relative(str(input.path), cwd), str(input.glob), str(input.type)].filter(Boolean)
      return { main: str(input.pattern), detail: where.length ? `in ${where.join(' ')}` : '' }
    }
    case 'Glob':
      return { main: str(input.pattern), detail: relative(str(input.path), cwd) }
    case 'LS':
      return { main: path || '.' }
    case 'WebFetch':
      return { main: str(input.url) }
    case 'WebSearch':
      return { main: str(input.query) }
    case 'Task':
    case 'Agent':
      return { main: str(input.description), detail: str(input.subagent_type) }
    case 'TodoWrite': {
      const todos = Array.isArray(input.todos) ? (input.todos as { status?: string }[]) : []
      const done = todos.filter(todo => todo.status === 'completed').length
      return { main: plural(todos.length, 'todo'), detail: `${done} done` }
    }
    case 'Skill':
      return { main: str(input.skill) || str(input.command), detail: str(input.args) }
    case 'AskUserQuestion': {
      const questions = Array.isArray(input.questions) ? (input.questions as { question?: string }[]) : []
      return { main: str(questions[0]?.question), detail: questions.length > 1 ? `+${questions.length - 1} more` : '' }
    }
  }

  const first = Object.values(input).find(value => typeof value === 'string')
  return { main: firstLine(str(first)) }
}

export type Status = { icon: string; color: string; dim?: boolean }

export function statusOf(call: { isRunning: boolean; isErrored: boolean; isInterrupted: boolean }): Status {
  if (call.isInterrupted) return { icon: GLYPH.interrupted, color: 'warning', dim: true }
  if (call.isErrored) return { icon: GLYPH.error, color: 'error' }
  if (call.isRunning) return { icon: GLYPH.running, color: 'warning' }
  return { icon: GLYPH.ok, color: 'success', dim: true }
}

export function durationOf(ms: number): string {
  if (ms < 1000) return `${Math.round(ms)}ms`
  const seconds = ms / 1000
  if (seconds < 60) return `${seconds.toFixed(1)}s`
  const minutes = Math.floor(seconds / 60)
  return `${minutes}m ${Math.round(seconds % 60)}s`
}

export const MODE_ICONS: Record<string, string> = {
  requesting: GLYPH.upload,
  responding: GLYPH.comment,
  thinking: GLYPH.lightbulb,
  'tool-input': GLYPH.gear,
  'tool-use': GLYPH.tools,
}
