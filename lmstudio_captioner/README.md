
# LM Studio Video Captioner (simple frontend)

A minimal local web app that wraps the LM Studio OpenAI-compatible API to caption short video clips.
It extracts frames from a clip (uniformly spaced or the first N), sends them to your loaded VLM model,
and writes `.txt` captions (batch mode) or shows them in a chat-like UI (single-clip mode).

## Prefill behavior
LM Studio's API does not support true assistant prefilling. Any prefix you supply is sent as an extra
`assistant` message and the model treats it as a prior reply rather than continuing from it.

## Prereqs

- Python 3.10+
- `pip install -r requirements.txt`
- LM Studio running locally. Load a **vision model**, open the **Developer** tab, enable the API server
  (default base URL `http://localhost:1234/v1`), and copy the model's name into the app's model field.

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
cd lmstudio_captioner
pip install -r requirements.txt
python app.py
```
Then open http://localhost:5057/

## Notes / Limits

- Batch cancel is UI-only in this simple version.
- Supported video extensions: .mp4, .mov, .avi, .webm, .mkv, .m4v
