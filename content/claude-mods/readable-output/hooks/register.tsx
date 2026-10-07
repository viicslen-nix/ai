import type { Register, RenderElement, ToolGroupCall } from 'claude-code'

import { type Message, closeStep, followedByTool, isKnown, observe, openStep, pending } from './narration'
import { GLYPH, MODE_ICONS, PALETTE, durationOf, statusOf, styleOf, summaryOf } from './tools'

// Past this the engine's own drawing is kept: one tree draws at most 100000 characters.
const MAX_TEXT = 60000
const MAX_PROMPT = 4000
const NARRATION_WAIT_MS = 1500

// Results drawn under their row; every other tool's shows only when it errs.
const SHOWN_RESULTS = new Set(['Edit', 'MultiEdit', 'Write', 'NotebookEdit'])

let cwd: string | undefined

async function cwdOf($: { session: { cwd: () => Promise<string> } }): Promise<string> {
  if (cwd === undefined) cwd = await $.session.cwd().catch(() => '')
  return cwd
}

let messages: { at: number; list: Promise<Message[]> } | undefined

function messagesOf($: any): Promise<Message[]> {
  const now = Date.now()
  if (!messages || now - messages.at > 500) {
    const list = $.session.messages().then(
      (m: unknown) => (Array.isArray(m) ? m : []),
      () => [],
    )
    messages = { at: now, list }
  }
  return messages.list
}

async function isNarration($: any, text: string, waitMs: number): Promise<boolean> {
  const needle = text.trim()
  if (!needle) return false
  if (isKnown(needle)) return true
  const verdict = pending(needle)
  if (verdict) {
    if (waitMs <= 0) return false
    const timeout = $.clock.sleep(waitMs).then(
      () => false,
      () => false,
    )
    return Promise.race([verdict, timeout])
  }
  return followedByTool(await messagesOf($), needle)
}

async function* watchStep($: any, e: any, next: any) {
  const step = openStep()
  try {
    const stream = next(e)
    for await (const chunk of stream) {
      observe(step, chunk)
      yield chunk
    }
    return await stream.result
  } finally {
    closeStep(step)
  }
}

function Bar({ Box, color, children }: { Box: any; color: string; children: unknown }) {
  return (
    <Box flexDirection="row">
      <Box width={1} flexShrink={0} backgroundColor={color} />
      <Box paddingLeft={1} flexGrow={1} flexShrink={1} flexDirection="column">
        {children}
      </Box>
    </Box>
  )
}

function badge(tags: { Box: any; Text: any }, color: string, icon: string, label: string, loud = false) {
  const { Box, Text } = tags
  return (
    <Box flexShrink={0}>
      <Text backgroundColor={color} color={loud ? PALETTE.loudInk : PALETTE.ink} bold={loud}>
        {` ${icon} ${label} `}
      </Text>
    </Box>
  )
}

function groupStatus(calls: ReadonlyArray<ToolGroupCall>) {
  return statusOf({
    isRunning: calls.some(call => call.isRunning),
    isErrored: calls.some(call => call.isErrored),
    isInterrupted: calls.some(call => call.isInterrupted),
  })
}

async function render($: any, e: any, next: (e: any) => Promise<RenderElement>): Promise<RenderElement> {
  if (e.surface !== 'terminal') return next(e)
  const tags = $.ui.resolve(e)
  const { Box, Text } = tags
  const p = e.props

  switch (e.component) {
    case 'ToolUse': {
      const style = styleOf(p.tool)
      const status = statusOf(p)
      const summary = summaryOf(p.tool, p.input, p.output, await cwdOf($))
      const loud = p.tool === 'Skill'
      return (
        <Box flexDirection="row" gap={1}>
          <Text color={status.color} dimColor={status.dim}>
            {status.icon}
          </Text>
          {badge(tags, loud ? PALETTE.loudSkill : style.color, style.icon, style.label, loud)}
          <Box flexShrink={1}>
            <Text wrap="truncate-end" bold={loud}>
              {summary.main}
              {summary.detail ? <Text dimColor>{`  ${summary.detail}`}</Text> : null}
            </Text>
          </Box>
          {summary.added ? <Text color="diffAdded">{`+${summary.added}`}</Text> : null}
          {summary.removed ? <Text color="diffRemoved">{`-${summary.removed}`}</Text> : null}
        </Box>
      )
    }

    case 'ToolResult': {
      if (!p.isErrored && !SHOWN_RESULTS.has(p.tool)) return <Box />
      const color = p.isErrored ? 'error' : PALETTE.rail
      return (
        <Box paddingLeft={2}>
          <Bar Box={Box} color={color}>
            {await next(e)}
          </Bar>
        </Box>
      )
    }

    case 'ToolGroup': {
      if (p.isExpanded) return next(e)
      const calls: ReadonlyArray<ToolGroupCall> = p.calls
      const counts = new Map<string, { style: ReturnType<typeof styleOf>; n: number }>()
      for (const call of calls) {
        const style = styleOf(call.tool)
        const seen = counts.get(style.label)
        if (seen) seen.n += 1
        else counts.set(style.label, { style, n: 1 })
      }
      const status = groupStatus(calls)
      const shown = calls.find(call => call.isRunning) ?? calls[calls.length - 1]
      const current = shown ? summaryOf(shown.tool, shown.input, undefined, await cwdOf($)).main : ''
      return (
        <Box flexDirection="row" gap={1}>
          <Text color={status.color} dimColor={status.dim}>
            {status.icon}
          </Text>
          {[...counts.values()].map(({ style, n }) =>
            badge(tags, style.color, style.icon, n > 1 ? `${style.label} ×${n}` : style.label),
          )}
          {current ? (
            <Box flexShrink={1}>
              <Text dimColor wrap="truncate-end">
                {current}
              </Text>
            </Box>
          ) : null}
        </Box>
      )
    }

    case 'UserMessage': {
      if (p.origin?.kind !== 'composer' || p.text.length > MAX_PROMPT) return next(e)
      return (
        <Box flexDirection="row" marginTop={1}>
          <Box flexShrink={0} paddingX={1} backgroundColor={PALETTE.user}>
            <Text color={PALETTE.ink}>
              {GLYPH.account}
            </Text>
          </Box>
          <Box flexGrow={1} flexShrink={1} paddingX={1} backgroundColor="userMessageBackground">
            <Text>{p.text}</Text>
          </Box>
        </Box>
      )
    }

    case 'AssistantMessage': {
      if (p.text.length > MAX_TEXT) return next(e)
      const remainingMs: number = (next as any).budget?.remainingMs ?? Infinity
      const waitMs = Math.min(NARRATION_WAIT_MS, remainingMs - 500)
      if (await isNarration($, p.text, waitMs)) {
        const lines = p.text.trim().split('\n')
        const more = lines.length > 1 ? `  +${lines.length - 1} lines` : ''
        return (
          <Bar Box={Box} color={PALETTE.rail}>
            <Text dimColor italic wrap="truncate-end">
              {`${GLYPH.comment} ${lines[0]}${more}`}
            </Text>
          </Bar>
        )
      }
      return (
        <Bar Box={Box} color={PALETTE.claude}>
          {await next(e)}
        </Bar>
      )
    }

    case 'Spinner': {
      // The engine's spinner is a margined column; wrapping it in a row misaligns, so only its word changes.
      const icon = MODE_ICONS[p.mode]
      if (!icon) return next(e)
      return next({ ...e, props: { ...p, word: `${icon} ${p.word}` } })
    }

    case 'TurnDuration':
      return (
        <Box flexDirection="row" gap={1} marginTop={1}>
          <Text color="inactive">──</Text>
          <Text color="success" dimColor>
            {GLYPH.ok}
          </Text>
          <Text color="inactive">{p.word}</Text>
          {badge(tags, PALETTE.done, GLYPH.watch, durationOf(p.durationMs))}
          <Text color="inactive">──</Text>
        </Box>
      )
  }

  return next(e)
}

export const register: Register = on => {
  on('ui.render', render)
  on('turn.step', watchStep)
}
