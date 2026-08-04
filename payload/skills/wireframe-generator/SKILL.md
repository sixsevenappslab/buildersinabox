---
name: wireframe-generator
description: Generates wireframes and mockups with the Gemini image API (bring your own GEMINI_API_KEY) for visual references in FEAT specs within the SDD flow, or whenever a quick wireframe/mockup of a screen is requested.
disable-model-invocation: true
---

# Wireframe Generator — Gemini Image Generation

## Purpose

Generate wireframes, mockups, and visual references for FEAT specs using
Google's Gemini image-generation model.

## Who uses it

| Context | Use case |
|---------|----------|
| `sdd-spec-writer` / `ui-ux-consultant` | Product wireframes, UX flows, UI states |
| `sdd-growth` | Landing page mockups, banners, CTAs |

## Requirements (bring your own key)

This skill calls the Gemini API with **your own** Google AI Studio key — it is
not bundled and nothing works without it.

- **API key:** `GEMINI_API_KEY` environment variable. Get one at
  https://aistudio.google.com/apikey (a free tier exists).
- **Script:** `~/.agents/skills/wireframe-generator/scripts/generate-wireframe.sh`
- **Model:** configurable via `GEMINI_IMAGE_MODEL` (the script has a sensible default).

**If `GEMINI_API_KEY` is not set**, the script exits with a clear message. In
that case: tell the user this skill needs a Google AI Studio key, show them how
to set it (below), and stop gracefully — don't retry, don't fail cryptically,
and offer to continue the task without images (e.g. describe the screens in
text or a mermaid diagram instead).

```bash
# In the shell profile or the project's .env
export GEMINI_API_KEY="your-api-key"
```

## Usage

### Basic command

```bash
~/.agents/skills/wireframe-generator/scripts/generate-wireframe.sh \
  --prompt "Mobile login screen with email field, password field, and blue login button. Clean wireframe style, grayscale." \
  --output <project>/specs/assets/FEAT-NNN/login-wireframe.png \
  --style wireframe
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--prompt` | Yes | Description of what to generate |
| `--output` | Yes | Path to save the image (PNG) |
| `--style` | No | Preset style: `wireframe`, `mockup`, `sketch` (default: wireframe) |
| `--model` | No | Gemini model override |

### Preset styles

Styles add prompt prefixes for consistency:

- **wireframe**: "Clean wireframe style, grayscale, no colors, simple lines and shapes. UI wireframe of:"
- **mockup**: "High-fidelity mobile app mockup, modern UI, clean design. Mockup of:"
- **sketch**: "Hand-drawn sketch style, rough lines, quick concept. Sketch of:"

## Flow in SDD

```
1. sdd-coordinator creates FEAT-NNN → "Visual references" section says "generation pending"
2. sdd-spec-writer analyzes requirements and generates wireframes:
   - Identifies key screens
   - Generates 1 wireframe per screen/state
   - Saves to specs/assets/FEAT-NNN/
3. Updates the "Visual references" section with the paths
4. Implementation uses the visual reference for the frontend
```

## File conventions

```
specs/assets/FEAT-NNN/
├── wireframe-home.png          # Main screen
├── wireframe-detail.png        # Detail view
├── wireframe-flow.png          # Full flow
├── mockup-landing.png          # Landing (if growth applies)
└── README.md                   # Description of each asset
```

## Prompt engineering — tips

### For effective wireframes
- Specify the platform: "mobile app", "web desktop", "responsive"
- Describe the elements: "header with logo and hamburger menu, main content area with card list"
- Include states: "empty state with illustration and CTA button"
- Reference a style: "similar to Stripe's checkout page"

### Full prompt example
```
Mobile app screen for a financial wellness app.
Screen: Monthly budget overview.
Elements:
- Top: Month selector (< March 2026 >)
- Summary card: Total budget, spent, remaining with progress bar
- Category list: Each with icon, name, amount spent / budgeted
- Bottom: Floating action button to add expense
Style: Clean, modern, iOS-like. Grayscale wireframe.
```

## Limitations

- Wireframes are a **visual guide**, not final design
- Quality depends on the prompt — iterate if needed
- For pixel-perfect designs, use a design tool (Figma etc.) externally
- The model may not capture complex interactions (use mermaid/flowcharts for flows)
