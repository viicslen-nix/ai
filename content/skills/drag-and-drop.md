---
name: drag-and-drop
description: Interaction defaults for drag-and-drop — lifted preview, item-sized placeholder, refused drops, keyboard dragging, collapsible and grouped containers. Use when building or reviewing anything users drag: sortable lists, form builders, kanban boards, file trees, dashboards with movable widgets.
---

# Drag and drop

Every drag involves the same few decisions. Users never notice them when they
are right and always feel them when they are wrong. Apply each one below
unless the product says otherwise, and when reviewing, check each one by name.

## 1. Lift

The drag preview must look picked up, not slid flat:

- `scale(1.03)`, shadow raised about 8px of elevation, `rotate(3deg)` (Trello's
  tilt). Use a smaller tilt (1–2°) on wide items like form fields or table rows,
  where 3° swings the far edge too much.
- Show a grab cursor on hover and a grabbing cursor while dragging. Show a
  visible handle when only part of the item starts a drag.
- Under `prefers-reduced-motion`, keep the scale and shadow and drop the tilt
  and any animated transitions.

A preview that is flat and the same size as the item reads as "not grabbed".

## 2. Placeholder = item size

The drop slot is a dashed or tinted box exactly as big as the dragged item, not
a thin insertion line.

- Siblings make room once, when the slot opens, so the drop itself causes
  **zero layout shift**. A thin line makes everything after it jump on drop.
- Measure the real size of the dragged item, because items vary (a textarea
  field is taller than a checkbox).
- A drag from a palette (adding a new form field or widget) opens a slot the
  size of the item it will create, not the size of the palette chip.

## 3. Refuse drops visibly

When a target has a rule (a capacity limit, an allowed type, a nesting depth):

- Show the rule before the drag. A limit lives on the target itself
  (`In progress 3 / 4`, `Fields 9 / 10`), neutral below the limit and in the
  warning colour at the limit.
- During the drag, a target that will refuse the item shows it (dimmed, a
  no-drop cursor) and opens no placeholder.
- A refused drop animates the item back to where it came from, and a toast near
  the target gives the reason (`WIP limit reached · finish one first`). Never
  accept a breaking drop silently, and never accept it with only a warning.

## 4. Containers: collapse and group

These apply when items live in containers (columns, form sections, folders,
lanes):

- **Collapse instead of scroll.** When containers overflow the viewport, let
  each one collapse to a slim rail or header showing its name and count
  (`Done · 42`, `Address · 4 fields`). Use that instead of scrolling sideways or
  making the user scroll past a long section.
- A collapsed container is still a drop target: hovering over it during a drag
  expands it after a short delay, or it accepts the drop at its end.
- Persist the collapsed state for each user.
- **Group within one surface instead of splitting it.** Split work by team or
  type with lanes or sections inside one board or form. Do not create separate
  boards or forms, because that gives you two sources of truth for counts and
  limits. Each group header shows its own counts and can be collapsed. Totals
  and limits on the shared axis cover the whole surface.

## Keyboard

Every drag needs a keyboard path: focus an item, Space to lift, arrow keys to
move between slots and containers, Space to drop, Esc to cancel. Announce each
move through a live region. Refused-drop rules apply to keyboard drops too.
