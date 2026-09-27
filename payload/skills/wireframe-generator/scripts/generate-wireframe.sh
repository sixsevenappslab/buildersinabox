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

# A control character in the key cannot be escaped away: curl reads the config
# line by line, so a newline silently truncates the key and a carriage return
# splits the outgoing HTTP header. Both fail as a corrupted request rather than
# an error, so reject them here. Usually this means the key was pasted from a
# CRLF file and carries a stray \r.
if [[ "$GEMINI_API_KEY" == *[[:cntrl:]]* ]]; then
  echo "❌ Error: GEMINI_API_KEY contains a control character (a stray newline or carriage return?)"
  echo "Check where it is set — a key copied out of a Windows-style file often keeps a hidden \\r"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ Error: jq is required to build the request and read the response"
  echo "Install it with: sudo apt-get install -y jq"
  exit 1
fi

# The model name goes into the request path. Keep it to the characters real
# model names use, so a value like 'x?key=other' cannot bend the URL.
if [[ ! "$MODEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "❌ Error: invalid model name: $MODEL"
  echo "Expected letters, digits, dots, underscores or hyphens (e.g. gemini-3.1-flash-image-preview)"
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

# Build the request body with jq so the prompt is escaped properly. A prompt
# containing a double quote, a backslash or a newline would otherwise produce
# malformed JSON and the API would reject it.
REQUEST_BODY=$(jq -n --arg text "$FULL_PROMPT" '{
  contents: [{ parts: [{ text: $text }] }],
  generationConfig: { responseModalities: ["TEXT", "IMAGE"] }
}')

# The key is fed to curl on stdin, never as an argument. Anything in curl's
# argv — a ?key= in the URL and an -H header alike — shows up in `ps` for
# every other user on the machine. With --config the argv is just
# "curl --config -". Escape \ and ", which are what curl's config quoting
# treats specially; control characters are rejected above, because escaping
# cannot save them.
ESCAPED_KEY=${GEMINI_API_KEY//\\/\\\\}
ESCAPED_KEY=${ESCAPED_KEY//\"/\\\"}

RESPONSE=$(printf 'header = "x-goog-api-key: %s"\n' "$ESCAPED_KEY" \
  | curl -s --config - \
      "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
      -H 'Content-Type: application/json' \
      -d "$REQUEST_BODY" 2>&1)

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
