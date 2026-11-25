---
name: ux-review
description: "UX/UI review criteria. Mobile-first evaluation, accessibility checks, design consistency, usability heuristics."
---

# UX/UI Review

## Mobile-First Checklist

| Criterion | Check |
|-----------|-------|
| Responsive breakpoints | Test at 375px, 768px, 1024px |
| Touch targets | ≥ 44×44px on all interactive elements |
| Loading states | Skeleton/spinner on async content |
| Error states | User-friendly message + retry action |
| Empty states | Illustration/copy + CTA when no data |
| Navigation | Consistent across all views, back works |
| Scroll | No horizontal overflow, smooth vertical |
| Forms | Labels visible, validation inline, keyboard type correct |

## Accessibility (WCAG AA)

| Criterion | Requirement |
|-----------|-------------|
| Color contrast | ≥ 4.5:1 text, ≥ 3:1 large text/UI components |
| Alt text | All meaningful images have descriptive alt |
| Keyboard nav | All actions reachable via Tab/Enter/Esc |
| Focus indicators | Visible focus ring on interactive elements |
| Screen reader | ARIA labels on icons, buttons, dynamic content |
| Motion | `prefers-reduced-motion` respected |
| Zoom | Readable at 200% zoom, no content cut off |

## Design Consistency

- **Typography:** uses defined scale (no arbitrary sizes)
- **Spacing:** 4px/8px grid system respected
- **Colors:** only palette tokens used (no hardcoded hex)
- **Components:** reuse existing library, don't reinvent
- **Icons:** same family/style throughout
- **Border radius:** consistent token across cards/buttons

## Nielsen's 10 Usability Heuristics

| # | Heuristic | One-liner |
|---|-----------|-----------|
| 1 | Visibility of system status | User always knows what's happening |
| 2 | Match real world | Use familiar language and concepts |
| 3 | User control & freedom | Easy undo, cancel, go back |
| 4 | Consistency & standards | Same action = same result everywhere |
| 5 | Error prevention | Prevent mistakes before they happen |
| 6 | Recognition over recall | Show options, don't make users memorize |
| 7 | Flexibility & efficiency | Shortcuts for experts, simple for novices |
| 8 | Aesthetic & minimal design | No clutter, every element earns its place |
| 9 | Help users recover from errors | Clear error messages with next steps |
| 10 | Help & documentation | Searchable, task-oriented, concise |

## Review Output Format

```
### UX Review: [Feature/PR]
Date: YYYY-MM-DD | Reviewer: Pablo

| Criterion | Status | Notes |
|-----------|--------|-------|
| Mobile 375px | ✅/⚠️/❌ | ... |
| Touch targets | ✅/⚠️/❌ | ... |
| Loading states | ✅/⚠️/❌ | ... |
| Error handling | ✅/⚠️/❌ | ... |
| Accessibility | ✅/⚠️/❌ | ... |
| Design consistency | ✅/⚠️/❌ | ... |
| Heuristics | ✅/⚠️/❌ | ... |

**Verdict:** APPROVED / NEEDS WORK
**Blockers:** (list any ❌ items)
**Suggestions:** (nice-to-have improvements)
```
