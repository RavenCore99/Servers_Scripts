# Hermes Design System Reference

*Extraído de Hermes Desktop el 2026-10-16*

## 🎨 Design Tokens (CSS Variables)

Use these in your CSS: `var(--token-name)`

### Stroke & Border

- **``--ui-stroke-primary…quaternary``** → `var(--`ui-stroke-primary…quaternary`)`
  - hairlines, in descending strength

- **``--ui-stroke-tertiary``** → `var(--`ui-stroke-tertiary`)`
  - the default in-panel divider / list hairline — and every bordered surface in the transcript

- **``--stroke-nous``** → `var(--`stroke-nous`)`
  - the overlay hairline (pairs with `shadow-nous`)

### Text Colors

- **``--ui-text-primary / -secondary / -tertiary``** → `var(--`ui-text-primary / -secondary / -tertiary`)`
  - text hierarchy

### Backgrounds & Fills

- **``--ui-bg-quaternary``** → `var(--`ui-bg-quaternary`)`
  - soft control fill (secondary button)

- **``--ui-widget-surface-background``** → `var(--`ui-widget-surface-background`)`
  - fill for inline chat widgets (`WIDGET_SHELL_CLASS`)

### Interactive States

- **``--chrome-action-hover``** → `var(--`chrome-action-hover`)`
  - hover fill for quiet controls

### Brand & Theme

- **``--theme-primary`, `--ui-accent``** → `var(--`theme-primary`, `ui-accent`)`
  - brand/accent

## 🧩 Components

### Loaders

- **Available Types**: 21 mathematical curve-based loaders
- **Default Type**: `rose-curve`
- **Description**: Mathematical curve-based loaders (lemniscate, rose curves, spirals, cardioids, etc.)
- **Implementation**: Uses requestAnimationFrame with parametric curves for smooth, performant animations

### Button

- **Variants**: 10 available
- **Sizes**: 12 available
- **Description**: Single Button component with variant and size props

### Widget Shell

- **CSS Class**: `rounded-3xl bg-(--ui-widget-surface-background) px-3.5 py-3`
- **Description**: Shared shell for inline transcript widgets (clarify, artifact cards)

## 📐 Design Principles

1. Flat, not boxed - No card-in-card, no divider borders inside a panel. Group with whitespace and a single hairline, never nested rounded boxes.

2. Borderless elevation for floating panels - Overlays float on shadow-nous + a --stroke-nous hairline, not thick framed boxes.

3. One primitive per concern - One Button, one set of control variants, one SearchField, one Loader, one ErrorState. Migrate onto them; don't fork.

4. Tokens, not literals - Reference CSS vars (--ui-*, --shadow-nous, --theme-*), never raw hex / ad-hoc rgba in components.

5. Style lives in the primitive - Variants and sizes own padding, radius, color, chrome. Call sites pass a variant/size, not className overrides that re-specify those.

6. Intent before automation - Surface useful actions and previews, but do not open panes, move focus, or navigate because a tool happened to produce something.

7. Immediate feedback - Direct manipulation updates the view first. Network or disk persistence reconciles afterward and rolls back visibly on failure.

## 💡 Usage Guidelines

### CSS Variables
```css
/* Import the design tokens */
@import './hermes-design-tokens.css';

/* Example usage */
.button {
  background-color: var(--ui-bg-quaternary);
  color: var(--ui-text-primary);
  border: 1px solid var(--ui-stroke-tertiary);
}
.panel {
  background-color: var(--ui-bg-quaternary);
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
  border: 1px solid var(--stroke-nous);
}
```

### Key Principles to Remember

1. **Flat over Boxed**: Use whitespace and single hairlines instead of nested boxes
2. **Tokens First**: Never hardcode colors - always use design tokens
3. **Immediate Feedback**: UI updates before network/disk persistence
4. **One Primitive**: Use the shared Button, Loader, etc. components
5. **Motion Follows State**: Animations should reflect state changes, not precede them

## 📁 File Structure

```
hermes-design-system/
├── hermes-design-system.json      # Complete specification
├── hermes-design-tokens.css       # CSS variables ready to import
└── HERMES_DESIGN_REFERENCE.md     # This reference guide
```
