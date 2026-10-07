import type { Register, RenderElement, ToolGroupCall } from 'claude-code'

import { GLYPH, MODE_ICONS, durationOf, statusOf, styleOf, summaryOf } from './tools'

// Past this the engine's own drawing is kept: one tree draws at most 100000 characters.
const MAX_TEXT = 60000
const MAX_PROMPT = 4000

let cwd: string | undefined

async function cwdOf($: { session: { cwd: () => Promise<string> } }): Promise<string> {
  if (cwd === undefined) cwd = await $.session.cwd().catch(() => '')
  return cwd
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

function badge(tags: { Box: any; Text: any }, color: string, icon: string, label: string) {
  const { Box, Text } = tags
  return (
    <Box flexShrink={0}>
      <Text backgroundColor={color} color="inverseText" bold>
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
      return (
        <Box flexDirection="row" gap={1}>
          <Text color={status.color}>{status.icon}</Text>
          {badge(tags, style.color, style.icon, style.label)}
          <Box flexShrink={1}>
            <Text wrap="truncate-end">
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
      const color = p.isErrored ? 'error' : styleOf(p.tool).color
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
          <Text color={status.color}>{status.icon}</Text>
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
          <Text backgroundColor="claude" color="inverseText" bold>
            {` ${GLYPH.account} `}
          </Text>
          <Box flexGrow={1} flexShrink={1} paddingX={1} backgroundColor="userMessageBackground">
            <Text>{p.text}</Text>
          </Box>
        </Box>
      )
    }

    case 'AssistantMessage': {
      if (p.text.length > MAX_TEXT) return next(e)
      return (
        <Bar Box={Box} color="claude">
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
          <Text color="success">{GLYPH.ok}</Text>
          <Text color="inactive">{p.word}</Text>
          {badge(tags, 'success', GLYPH.watch, durationOf(p.durationMs))}
          <Text color="inactive">──</Text>
        </Box>
      )
  }

  return next(e)
}

export const register: Register = on => {
  on('ui.render', render)
}
