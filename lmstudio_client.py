#!/usr/bin/env python3
import sys
import requests

LMSTUDIO_ENDPOINT = "http://127.0.0.1:1234/v1/chat/completions"
LMSTUDIO_MODEL = "qwen/qwen3-vl-30b"  # your model

def generate(prompt: str,
             max_tokens: int = 512,
             temperature: float = 0.7,
             system_prompt: str = "You are a helpful assistant.") -> str:
    payload = {
        "model": LMSTUDIO_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }

    r = requests.post(LMSTUDIO_ENDPOINT, json=payload, timeout=120)
    r.raise_for_status()
    data = r.json()

    # OpenAI-style chat completion
    if "choices" in data and data["choices"]:
        return data["choices"][0]["message"]["content"].strip()

    # fallback: just dump raw if unexpected
    return str(data)

def main():
    if len(sys.argv) < 2:
        print("Usage: lmstudio_client.py 'your prompt here'")
        sys.exit(1)

    prompt = sys.argv[1]
    text = generate(prompt)
    print(text)

if __name__ == "__main__":
    main()
