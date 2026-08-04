#!/usr/bin/env bash
# generate-wireframe.sh — Generates wireframes/mockups using the Gemini API (image generation)
# Usage: ./generate-wireframe.sh --prompt "description" --output path/to/image.png [--style wireframe|mockup|sketch] [--model model-name]

set -euo pipefail

# --- Load secrets if available ---
if [[ -f ~/.env.gemini-secrets ]]; then
  set -a
  # shellcheck source=/dev/null
  source ~/.env.gemini-secrets
  set +a
fi

# --- Defaults ---
MODEL="${GEMINI_IMAGE_MODEL:-gemini-3.1-flash-image-preview}"
STYLE="wireframe"
PROMPT=""
OUTPUT=""

# --- Style prefixes ---
declare -A STYLE_PREFIX=(
  ["wireframe"]="Clean wireframe style, grayscale, no colors, simple lines and shapes, professional UI wireframe. "
  ["mockup"]="High-fidelity mobile app mockup, modern UI, clean design, realistic proportions. "
  ["sketch"]="Hand-drawn sketch style, rough lines, quick concept drawing. "
)

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --prompt) PROMPT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --style) STYLE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --prompt 'description' --output path/to/image.png [--style wireframe|mockup|sketch] [--model model-name]"
      echo ""
      echo "Styles: wireframe (default), mockup, sketch"
      echo "Requires: GEMINI_API_KEY environment variable"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Validate ---
if [[ -z "$PROMPT" ]]; then
  echo "❌ Error: --prompt is required"
  exit 1
fi

if [[ -z "$OUTPUT" ]]; then
  echo "❌ Error: --output is required"
  exit 1
fi

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "❌ Error: GEMINI_API_KEY environment variable is not set"
  echo "This skill is bring-your-own-key: get a free key at https://aistudio.google.com/apikey"
  echo "Then: export GEMINI_API_KEY=\"your-api-key\" (shell profile or project .env)"
  exit 1
fi

# --- Build full prompt ---
PREFIX="${STYLE_PREFIX[$STYLE]:-}"
FULL_PROMPT="${PREFIX}${PROMPT}"

# --- Create output directory ---
mkdir -p "$(dirname "$OUTPUT")"

# --- Call Gemini API ---
echo "🎨 Generating ${STYLE} with model ${MODEL}..."
echo "📝 Prompt: ${FULL_PROMPT}"

RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}" \
  -H 'Content-Type: application/json' \
  -d "{
    \"contents\": [{
      \"parts\": [{
        \"text\": \"${FULL_PROMPT}\"
      }]
    }],
    \"generationConfig\": {
      \"responseModalities\": [\"TEXT\", \"IMAGE\"]
    }
  }" 2>&1)

# --- Check for errors ---
ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty' 2>/dev/null)
if [[ -n "$ERROR" ]]; then
  echo "❌ API Error: $ERROR"
  exit 1
fi

# --- Extract image data ---
# Gemini returns image as base64 in inlineData
IMAGE_DATA=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[] | select(.inlineData) | .inlineData.data // empty' 2>/dev/null)

if [[ -z "$IMAGE_DATA" ]]; then
  # Check if there's text response instead
  TEXT_RESPONSE=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
  if [[ -n "$TEXT_RESPONSE" ]]; then
    echo "⚠️  Model returned text instead of image:"
    echo "$TEXT_RESPONSE"
  else
    echo "❌ No image data in response"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
  fi
  exit 1
fi

# --- Save image ---
echo "$IMAGE_DATA" | base64 -d > "$OUTPUT"
echo "✅ Saved to: $OUTPUT"
echo "📐 Size: $(du -h "$OUTPUT" | cut -f1)"
