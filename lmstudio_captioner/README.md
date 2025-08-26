
# LM Studio Video Captioner (simple frontend)

A minimal local web app that wraps the LM Studio OpenAI-compatible API to caption short video clips.
It extracts frames from a clip (uniformly spaced or the first N), sends them to your loaded VLM model,
and writes `.txt` captions (batch mode) or shows them in a chat-like UI (single-clip mode).

## Prefill behavior (fixed)
Assistant response prefill is implemented via **assistant-prefix continuation**:
we append a final `role="assistant"` message containing your prefix and set `add_generation_prompt=false`
so LM Studio / llama.cpp continues from that text. This gives a true prefix instead of a mere instruction.

## Prereqs

- Python 3.10+
- `pip install -r requirements.txt`
- LM Studio running locally with the **OpenAI API Server** enabled (default base URL `http://localhost:1234/v1`).
- A **vision model** loaded in LM Studio (e.g., Qwen2.5-VL-32B-Instruct).

If your LM Studio server uses a different port/base URL, set:
```
export LMSTUDIO_BASE_URL="http://localhost:1234/v1"
```
Optionally set the model name:
```
export LMSTUDIO_MODEL="qwen2.5-vl-32b-instruct"
```

## Run

```bash
cd lmstudio_captioner_fixed
pip install -r requirements.txt
python app.py
```
Then open http://localhost:5057/

## Notes / Limits

- Batch cancel is UI-only in this simple version.
- Supported video extensions: .mp4, .mov, .avi, .webm, .mkv, .m4v
