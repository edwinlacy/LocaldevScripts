#!/usr/bin/env python3
import sys
import json
import textwrap
import requests

LMSTUDIO_ENDPOINT = "http://127.0.0.1:1234/v1/chat/completions"
LMSTUDIO_MODEL = "qwen/qwen3-vl-30b"

SYSTEM_PROMPT = """You are a tool that generates tightly structured JSON for short-form vertical videos.

Return a JSON object ONLY, no extra text, in this exact shape:

{
  "title": "Short, hooky title",
  "duration_seconds": 60,
  "narration_style": "first-person | third-person | narrator",
  "scenes": [
    {
      "id": 1,
      "start_seconds": 0,
      "end_seconds": 8,
      "beat": "Short description of the dramatic beat.",
      "visual_prompt": "Prompt for an AI video/image model (no camera notes unless essential).",
      "narration_line": "Exact line of narration text to be spoken.",
      "keywords": ["tag1", "tag2"]
    }
  ]
}

Rules:
- Aim for 3–6 scenes for a ~60 second video.
- Make narration lines concise and speakable out loud.
- Visual prompts should focus on what to show on screen, not internal thoughts.
- Do NOT include backticks or markdown, ONLY raw JSON.
"""

def call_lmstudio(prompt: str,
                  max_tokens: int = 1024,
                  temperature: float = 0.7) -> str:
    payload = {
        "model": LMSTUDIO_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    r = requests.post(LMSTUDIO_ENDPOINT, json=payload, timeout=180)
    r.raise_for_status()
    data = r.json()
    if "choices" in data and data["choices"]:
        return data["choices"][0]["message"]["content"]
    raise RuntimeError(f"Unexpected LM Studio response: {data}")

def generate_story_json(user_prompt: str) -> dict:
    raw = call_lmstudio(user_prompt)
    # Try to parse JSON directly; if the model wraps in text, try to extract.
    raw_stripped = raw.strip()
    # Try to find first '{' and last '}' just in case.
    if not raw_stripped.startswith("{"):
        start = raw_stripped.find("{")
        end = raw_stripped.rfind("}")
        if start != -1 and end != -1 and end > start:
            raw_stripped = raw_stripped[start:end+1]

    try:
        return json.loads(raw_stripped)
    except json.JSONDecodeError as e:
        raise SystemExit(f"Failed to parse JSON from model output:\n{e}\n\nRaw output:\n{raw}")

def main():
    if len(sys.argv) < 2:
        print("Usage: generate_story_scenes.py 'high-level video idea/prompt'")
        sys.exit(1)

    user_prompt = sys.argv[1]
    story = generate_story_json(user_prompt)
    print(json.dumps(story, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
