#!/usr/bin/env python
import os
import json
import requests

LMSTUDIO_URL = os.environ.get("LMSTUDIO_URL", "http://localhost:1234/v1/chat/completions")
LMSTUDIO_MODEL = os.environ.get("LMSTUDIO_MODEL", "openai/gpt-oss-120b")


def call_lmstudio_structured(story_prompt: str, num_scenes: int = 8):
    """
    Call LM Studio with a JSON Schema so it MUST return valid JSON.
    We then strictly extract only valid scene descriptions.
    """

    response_format = {
        "type": "json_schema",
        "json_schema": {
            "name": "story_scenes",
            "strict": True,
            "schema": {
                "type": "object",
                "properties": {
                    "scenes": {
                        "type": "array",
                        "minItems": num_scenes,
                        "maxItems": num_scenes,
                        "items": {
                            "type": "object",
                            "properties": {
                                "index": {"type": "integer"},
                                "title": {"type": "string"},
                                "description": {"type": "string"},
                            },
                            "required": ["description"],
                        },
                    }
                },
                "required": ["scenes"],
            },
        },
    }

    messages = [
        {
            "role": "system",
            "content": (
                "You are an AI that ONLY returns JSON. "
                "You write short scene descriptions for vertical (9:16) videos. "
                "Do not add explanations or any text outside of JSON."
            ),
        },
        {
            "role": "user",
            "content": (
                f"Create {num_scenes} distinct scenes for a 60-second vertical video. "
                "Each scene should be visual-only (no dialogue), 1–2 sentences, "
                "and focus on what the camera sees. "
                "Return JSON that matches the provided schema."
            ),
        },
        {
            "role": "user",
            "content": story_prompt,
        },
    ]

    print(f"[LM Studio] Calling {LMSTUDIO_URL} with model {LMSTUDIO_MODEL}...")

    resp = requests.post(
        LMSTUDIO_URL,
        json={
            "model": LMSTUDIO_MODEL,
            "messages": messages,
            "response_format": response_format,
            "temperature": 0.7,
            "max_tokens": 800,
            "stream": False,
        },
        timeout=180,
    )
    resp.raise_for_status()
    data = resp.json()

    content = data["choices"][0]["message"]["content"]

    print("\n[LM Studio] Raw content (first 400 chars):\n", content[:400], "\n")

    # Parse the JSON returned as a string
    parsed = json.loads(content)

    scenes = parsed.get("scenes", [])
    if not isinstance(scenes, list) or not scenes:
        raise RuntimeError(f"No scenes in response: {parsed}")

    def is_good_description(text: str) -> bool:
        t = text.strip()
        # must be at least ~1 sentence
        if len(t) < 25:
            return False
        # require some alphanumeric content
        alnum = sum(ch.isalnum() for ch in t)
        if alnum < 10:
            return False
        # reject if it's basically just dots/commas
        if set(t) <= set(".,… "):
            return False
        return True

    descriptions = []

    for s in scenes:
        if not isinstance(s, dict):
            continue
        desc = (s.get("description") or "").strip()
        if not desc:
            continue
        if not is_good_description(desc):
            continue
        descriptions.append(desc)

    if not descriptions:
        raise RuntimeError(f"All scenes were empty or low-quality: {parsed}")

    # Force exactly num_scenes
    if len(descriptions) < num_scenes:
        last = descriptions[-1]
        descriptions += [last] * (num_scenes - len(descriptions))
    elif len(descriptions) > num_scenes:
        descriptions = descriptions[:num_scenes]

    return descriptions


if __name__ == "__main__":
    prompt = "A cinematic story about building a dual-4090 AI content rig and launching a viral short-form empire."
    scenes = call_lmstudio_structured(prompt, num_scenes=8)

    print("[Parsed scenes]")
    for i, s in enumerate(scenes, start=1):
        print(f"{i}. {s}")
