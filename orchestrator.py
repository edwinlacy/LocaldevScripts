#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import time
from typing import List, Dict, Any

import requests

# ==== LM Studio config ====
LMSTUDIO_URL = "http://127.0.0.1:1234/v1/chat/completions"
LMSTUDIO_MODEL = "maya1-i1"

# Placeholder string inside your Comfy workflow JSON
PROMPT_PLACEHOLDER = "__SCENE_PROMPT__"


# ============================================================
# LM STUDIO: GET SCENE PROMPTS
# ============================================================
def call_lmstudio(story_prompt: str, num_scenes: int) -> List[str]:
    """
    Call LM Studio and return a list of scene prompt strings.
    """
    system_msg = f"""You generate a storyboard for a short vertical video.

Return exactly {num_scenes} scenes in strict JSON like:

{{
  "scenes": [
    {{
      "title": "Short cinematic title",
      "description": "1–3 sentences describing the shot in visual detail."
    }}
  ]
}}

Rules:
- Respond ONLY with JSON, no extra commentary.
- The story should be about: {story_prompt}
"""

    payload = {
        "model": LMSTUDIO_MODEL,
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": story_prompt},
        ],
        "temperature": 0.7,
        "max_tokens": 512,
        "response_format": {"type": "text"},
    }

    print(f"[LM Studio] Calling {LMSTUDIO_URL} with model {LMSTUDIO_MODEL}")
    resp = requests.post(LMSTUDIO_URL, json=payload)
    if not resp.ok:
        print("[LM Studio] HTTP", resp.status_code)
        print("[LM Studio] Body:", resp.text)
        resp.raise_for_status()

    data = resp.json()
    content = data["choices"][0]["message"]["content"]

    print("[LM Studio] Raw content (first 400 chars):")
    print(content[:400])

    # Try direct JSON first
    try:
        parsed = json.loads(content)
    except json.JSONDecodeError:
        start = content.find("{")
        end = content.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise RuntimeError(
                "Failed to parse LM Studio JSON (no braces). First 400 chars:\n"
                + content[:400]
            )
        json_block = content[start : end + 1]
        try:
            parsed = json.loads(json_block)
        except json.JSONDecodeError as e:
            raise RuntimeError(
                "Failed to parse LM Studio JSON. First 400 chars:\n"
                + content[:400]
            ) from e

    scenes_raw = parsed.get("scenes", [])
    if not isinstance(scenes_raw, list) or len(scenes_raw) == 0:
        raise RuntimeError(f"LM Studio returned no scenes: {parsed}")

    scene_prompts: List[str] = []
    print("\n[Parsed scenes]")
    for i, scene in enumerate(scenes_raw, start=1):
        title = ""
        desc = ""

        if isinstance(scene, dict):
            title = (scene.get("title") or "").strip()
            desc = (scene.get("description") or "").strip()
        else:
            desc = str(scene).strip()

        if title and desc:
            full = f"{title}: {desc}"
        elif desc:
            full = desc
        elif title:
            full = title
        else:
            full = f"Scene {i}"

        scene_prompts.append(full)
        print(f"{i}. {full}")

    if len(scene_prompts) < num_scenes:
        last = scene_prompts[-1]
        scene_prompts += [last] * (num_scenes - len(scene_prompts))
    elif len(scene_prompts) > num_scenes:
        scene_prompts = scene_prompts[:num_scenes]

    return scene_prompts


# ============================================================
# WORKFLOW: INJECT SCENE PROMPT
# ============================================================
def inject_scene_prompt(workflow: Dict[str, Any], scene_prompt: str) -> Dict[str, Any]:
    """
    Deep copy the workflow JSON and replace PROMPT_PLACEHOLDER with scene_prompt in all strings.
    """

    def _replace(obj):
        if isinstance(obj, dict):
            return {k: _replace(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [_replace(v) for v in obj]
        if isinstance(obj, str):
            return obj.replace(PROMPT_PLACEHOLDER, scene_prompt)
        return obj

    return _replace(workflow)


# ============================================================
# COMFY: WATCH FOR NEW VIDEO OUTPUT
# ============================================================
def list_mp4s(folder: str) -> List[str]:
    return [
        os.path.join(folder, f)
        for f in os.listdir(folder)
        if f.lower().endswith(".mp4")
    ]


def wait_for_new_video(output_dir: str, known_files: set, timeout: int = 900) -> str:
    """
    Wait for a new .mp4 file to appear in output_dir that is not in known_files.
    Also wait for its size to stabilize.
    """
    start = time.time()
    print(f"[Comfy] Waiting for new .mp4 in {output_dir} (timeout {timeout}s)...")

    candidate = None

    while time.time() - start < timeout:
        current_files = set(list_mp4s(output_dir))
        new_files = current_files - known_files

        if new_files:
            candidate = max(new_files, key=lambda p: os.path.getmtime(p))
            print(f"[Comfy] Detected new video candidate: {candidate}")

            last_size = -1
            stable_count = 0
            while stable_count < 3:
                try:
                    size = os.path.getsize(candidate)
                except FileNotFoundError:
                    stable_count = 0
                    last_size = -1
                    time.sleep(1)
                    continue

                if size == last_size:
                    stable_count += 1
                else:
                    stable_count = 0
                    last_size = size

                time.sleep(1)

            print(f"[Comfy] File size stabilized at {last_size} bytes.")
            return candidate

        time.sleep(1)

    raise TimeoutError(
        f"No new .mp4 detected in {output_dir} within {timeout} seconds."
    )


# ============================================================
# COMFY: RUN ONE SCENE WITH RETRIES
# ============================================================
def run_scene_through_comfy(
    scene_index: int,
    scene_prompt: str,
    comfy_url: str,
    base_workflow: Dict[str, Any],
    comfy_output_dir: str,
    output_dir: str,
    max_retries: int,
    known_files: set,
) -> str:
    """
    Send a scene to a Comfy instance, wait for output video, copy to scene_NN.mp4.
    """
    print(
        f"\n========== Scene {scene_index} | Using {comfy_url} =========="
    )
    print(f"Prompt: {scene_prompt}")

    for attempt in range(1, max_retries + 1):
        print(f"[Scene {scene_index}] Attempt {attempt}/{max_retries}")
        try:
            scene_workflow = inject_scene_prompt(base_workflow, scene_prompt)

            payload = {"prompt": scene_workflow}
            print(f"[Comfy] POST {comfy_url}/prompt")
            resp = requests.post(f"{comfy_url}/prompt", json=payload)
            if not resp.ok:
                print(f"[Comfy] HTTP {resp.status_code}: {resp.text[:400]}")
                resp.raise_for_status()

            data = resp.json()
            prompt_id = data.get("prompt_id")
            node_errors = data.get("node_errors", {})
            if node_errors:
                print(f"[Comfy] Node errors: {node_errors}")

            print(f"[Comfy] prompt_id = {prompt_id}")

            video_path = wait_for_new_video(comfy_output_dir, known_files)
            known_files.add(video_path)

            os.makedirs(output_dir, exist_ok=True)
            scene_filename = f"scene_{scene_index:02d}.mp4"
            dest_path = os.path.join(output_dir, scene_filename)
            print(f"[Orchestrator] Copying {video_path} -> {dest_path}")
            shutil.copy2(video_path, dest_path)

            return dest_path

        except Exception as e:
            print(f"[Scene {scene_index}] Error on attempt {attempt}: {e}")
            if attempt == max_retries:
                raise

            time.sleep(3)

    raise RuntimeError(
        f"Scene {scene_index} failed to render after {max_retries} attempts."
    )


# ============================================================
# FFMPEG: CONCAT CLIPS
# ============================================================
def concat_clips(clip_paths: List[str], final_output: str) -> None:
    """
    Use ffmpeg concat demuxer to combine multiple mp4s into one.
    """
    if not clip_paths:
        raise ValueError("No clips to concatenate.")

    concat_list_path = os.path.join(
        os.path.dirname(final_output), "concat_list.txt"
    )

    with open(concat_list_path, "w", encoding="utf-8") as f:
        for p in clip_paths:
            f.write(f"file '{p}'\n")

    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        concat_list_path,
        "-c",
        "copy",
        final_output,
    ]

    print("[ffmpeg]", " ".join(cmd))
    proc = subprocess.run(cmd)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed with code {proc.returncode}")


# ============================================================
# MAIN
# ============================================================
def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--story-prompt",
        help="High-level story idea to send to LM Studio",
    )
    parser.add_argument(
        "--num-scenes",
        type=int,
        default=8,
        help="Number of scenes",
    )
    parser.add_argument(
        "--workflow-json",
        help="Path to WAN 2.2 workflow JSON",
    )
    parser.add_argument(
        "--comfy-urls",
        help="Comma-separated list of Comfy base URLs, e.g. http://127.0.0.1:8188,http://127.0.0.1:8288",
    )
    parser.add_argument(
        "--comfy-output-dir",
        help="ComfyUI output directory where .mp4 files appear",
    )
    parser.add_argument(
        "--output-dir",
        help="Where to store scene clips + final video",
    )
    parser.add_argument(
        "--scenes-json",
        help="Path to scenes JSON (for saving or loading scene prompts)",
    )
    parser.add_argument(
        "--generate-scenes-only",
        action="store_true",
        help="Only call LM Studio and write scenes JSON; do not call Comfy.",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=4,
        help="Max retries per scene when calling Comfy",
    )

    args = parser.parse_args()

    # Mode A: generate scenes only (LM Studio -> scenes.json)
    if args.generate_scenes_only:
        if not args.story_prompt:
            raise SystemExit("--story-prompt is required with --generate-scenes-only")
        if not args.num_scenes:
            raise SystemExit("--num-scenes is required with --generate-scenes-only")
        if not args.scenes_json:
            raise SystemExit("--scenes-json is required with --generate-scenes-only")

        print("[Mode] Generate scenes only (LM Studio -> scenes JSON)")
        scene_prompts = call_lmstudio(args.story_prompt, args.num_scenes)

        os.makedirs(os.path.dirname(args.scenes_json), exist_ok=True)
        with open(args.scenes_json, "w", encoding="utf-8") as f:
            json.dump({"scenes": scene_prompts}, f, indent=2)

        print(f"[Scenes] Wrote {len(scene_prompts)} scenes to {args.scenes_json}")
        return

    # Mode B: render video (with or without LM Studio)
    missing = []
    if not args.workflow_json:
        missing.append("--workflow-json")
    if not args.comfy_urls:
        missing.append("--comfy-urls")
    if not args.comfy_output_dir:
        missing.append("--comfy-output-dir")
    if not args.output_dir:
        missing.append("--output-dir")

    if missing:
        raise SystemExit(
            "Missing required arguments for rendering: " + ", ".join(missing)
        )

    comfy_urls = [u.strip() for u in args.comfy_urls.split(",") if u.strip()]
    if not comfy_urls:
        raise SystemExit("No valid URLs in --comfy-urls")

    print("[Config] Comfy instances:")
    for u in comfy_urls:
        print(" -", u)

    # Determine where scene prompts come from
    scene_prompts: List[str]

    if args.scenes_json and os.path.exists(args.scenes_json):
        print(f"[Scenes] Loading existing scenes from {args.scenes_json}")
        with open(args.scenes_json, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and "scenes" in data:
            raw = data["scenes"]
        else:
            raw = data

        scene_prompts = []
        for i, s in enumerate(raw, start=1):
            if isinstance(s, str):
                scene_prompts.append(s)
            elif isinstance(s, dict):
                p = s.get("prompt") or s.get("description") or ""
                scene_prompts.append(str(p))
            else:
                scene_prompts.append(str(s))

        print(f"[Scenes] Loaded {len(scene_prompts)} scenes from file.")

    else:
        if not args.story_prompt:
            raise SystemExit(
                "No --scenes-json file found and no --story-prompt provided; "
                "cannot generate scenes."
            )
        print("[Scenes] No scenes JSON found. Calling LM Studio now...")
        scene_prompts = call_lmstudio(args.story_prompt, args.num_scenes)

        if args.scenes_json:
            os.makedirs(os.path.dirname(args.scenes_json), exist_ok=True)
            with open(args.scenes_json, "w", encoding="utf-8") as f:
                json.dump({"scenes": scene_prompts}, f, indent=2)
            print(
                f"[Scenes] Wrote {len(scene_prompts)} scenes to {args.scenes_json}"
            )

    if args.num_scenes and len(scene_prompts) != args.num_scenes:
        print(
            f"[Scenes] Adjusting scene count from {len(scene_prompts)} to {args.num_scenes}"
        )
        if len(scene_prompts) < args.num_scenes:
            last = scene_prompts[-1]
            scene_prompts += [last] * (args.num_scenes - len(scene_prompts))
        else:
            scene_prompts = scene_prompts[: args.num_scenes]

    with open(args.workflow_json, "r", encoding="utf-8") as f:
        base_workflow = json.load(f)

    os.makedirs(args.comfy_output_dir, exist_ok=True)
    known_files = set(list_mp4s(args.comfy_output_dir))

    clip_paths: List[str] = []
    num_instances = len(comfy_urls)

    for idx, prompt in enumerate(scene_prompts, start=1):
        url = comfy_urls[(idx - 1) % num_instances]
        clip_path = run_scene_through_comfy(
            scene_index=idx,
            scene_prompt=prompt,
            comfy_url=url,
            base_workflow=base_workflow,
            comfy_output_dir=args.comfy_output_dir,
            output_dir=args.output_dir,
            max_retries=args.max_retries,
            known_files=known_files,
        )
        clip_paths.append(clip_path)

    final_video = os.path.join(args.output_dir, "final_video.mp4")
    concat_clips(clip_paths, final_video)
    print(f"[Done] Final video: {final_video}")


if __name__ == "__main__":
    main()
