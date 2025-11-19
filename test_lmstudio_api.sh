#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="http://127.0.0.1:1234/v1/chat/completions"
MODEL="qwen/qwen3-vl-30b"   # your LM Studio model

PROMPT=${1:-"Give me 3 short, cinematic scene ideas for a 60-second TikTok video."}

echo "Hitting LM Studio at: ${ENDPOINT}"
echo "Model: ${MODEL}"
echo "Prompt: ${PROMPT}"
echo

curl -sS "${ENDPOINT}" \
  -H "Content-Type: application/json" \
  -d @- <<EOF | jq .
{
  "model": "${MODEL}",
  "messages": [
    { "role": "system", "content": "You are a creative assistant for short-form vertical video content." },
    { "role": "user", "content": "${PROMPT}" }
  ],
  "max_tokens": 512,
  "temperature": 0.7
}
EOF
