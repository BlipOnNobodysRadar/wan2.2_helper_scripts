
import os
import base64
import io
import json
from flask import Flask, render_template, request, jsonify
import requests
import cv2
from PIL import Image

# ------------------ Config ------------------
LMSTUDIO_BASE_URL = os.environ.get("LMSTUDIO_BASE_URL", "http://localhost:1234/v1")
DEFAULT_MODEL = os.environ.get("LMSTUDIO_MODEL", "qwen2.5-vl-32b-instruct")  # Change to your loaded model name
ALLOWED_EXTS = {".mp4", ".mov", ".avi", ".webm", ".mkv", ".m4v"}

app = Flask(__name__)

# ------------------ Helpers ------------------
def allowed_video(path:str)->bool:
    return os.path.splitext(path)[1].lower() in ALLOWED_EXTS

def frame_indices(total_frames:int, num_frames:int, sampling:str):
    if total_frames <= 0:
        return []
    n = max(1, int(num_frames))
    if sampling == "head":
        return list(range(min(n, total_frames)))
    # uniform
    if n == 1:
        return [0]
    step = (total_frames - 1) / (n - 1)
    return [int(round(i * step)) for i in range(n)]

def extract_frames(video_path:str, num_frames:int, sampling:str):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Failed to open video: {video_path}")
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    idxs = frame_indices(total, num_frames, sampling)
    images = []
    for idx in idxs:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ok, frame = cap.read()
        if not ok:
            continue
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        pil = Image.fromarray(frame_rgb)
        buf = io.BytesIO()
        pil.save(buf, format="JPEG", quality=90)
        b64 = base64.b64encode(buf.getvalue()).decode("utf-8")
        images.append(f"data:image/jpeg;base64,{b64}")
    cap.release()
    return images

def call_lmstudio_vision(images_data_urls, system_prompt:str, model:str, prefill:str=""):
    # Build user content with images
    user_content = [{"type":"text","text":"You are given a few frames sampled from a short video clip. Write a single caption that describes the clip as a whole."}]
    for url in images_data_urls:
        user_content.append({"type":"image_url","image_url":{"url": url}})

    # Messages: system + user (+ optional assistant prefill)
    messages = [
        {"role":"system","content": system_prompt.strip()},
        {"role":"user","content": user_content}
    ]

    payload = {
        "model": model or DEFAULT_MODEL,
        "messages": messages,
        "temperature": 0.2,
        # Default: add generation prompt so the model starts a new assistant turn
        "add_generation_prompt": True
    }

    # True assistant-prefix prefill:
    # LM Studio / llama.cpp continues the last assistant message when
    # add_generation_prompt=False and the final message is role=assistant.
    if prefill and prefill.strip():
        messages.append({"role":"assistant","content": prefill})
        payload["add_generation_prompt"] = False

    url = f"{LMSTUDIO_BASE_URL}/chat/completions"
    try:
        r = requests.post(url, json=payload, timeout=300)
        r.raise_for_status()
    except Exception as e:
        raise RuntimeError(f"LM Studio API error: {e}")
    data = r.json()
    try:
        return data["choices"][0]["message"]["content"].strip()
    except Exception:
        return json.dumps(data, indent=2)

# ------------------ Routes ------------------
@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/chat-caption", methods=["POST"])
def chat_caption():
    f = request.files.get("file")
    if not f:
        return jsonify({"error":"No file uploaded"}), 400
    system_prompt = request.form.get("system_prompt","You caption videos for dataset creation. Respond with ONLY the caption.")
    model = request.form.get("model", DEFAULT_MODEL)
    prefill = request.form.get("prefill","")
    try:
        num_frames = int(request.form.get("num_frames","5"))
    except:
        num_frames = 5
    sampling = request.form.get("sampling_type","uniform")
    tmpdir = "tmp_uploads"
    os.makedirs(tmpdir, exist_ok=True)
    video_path = os.path.join(tmpdir, f.filename)
    f.save(video_path)
    if not allowed_video(video_path):
        os.remove(video_path)
        return jsonify({"error":"Unsupported file extension"}), 400
    try:
        imgs = extract_frames(video_path, num_frames, sampling)
        if not imgs:
            raise RuntimeError("No frames extracted")
        caption = call_lmstudio_vision(imgs, system_prompt, model, prefill=prefill)
        return jsonify({"caption": caption, "frames_used": len(imgs)})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        try:
            os.remove(video_path)
        except:
            pass

@app.route("/api/batch-caption", methods=["POST"])
def batch_caption():
    data = request.get_json(force=True)
    target_folder = data.get("target_folder","").strip()
    system_prompt = data.get("system_prompt","You caption videos for dataset creation. Respond with ONLY the caption.")
    model = data.get("model", DEFAULT_MODEL)
    prefill = data.get("prefill","")
    num_frames = int(data.get("num_frames", 5))
    sampling = data.get("sampling_type", "uniform")
    overwrite = bool(data.get("overwrite", False))
    prepend_existing = bool(data.get("prepend_existing", False))

    if not target_folder or not os.path.isdir(target_folder):
        return jsonify({"error":"Invalid target folder"}), 400

    results = []
    files = [p for p in os.listdir(target_folder) if allowed_video(os.path.join(target_folder, p))]
    files.sort()
    for fn in files:
        video_path = os.path.join(target_folder, fn)
        base, _ = os.path.splitext(video_path)
        out_txt = base + ".txt"

        if os.path.exists(out_txt) and not overwrite and not prepend_existing:
            results.append({"file": fn, "skipped": True, "reason": "caption exists"})
            continue

        try:
            imgs = extract_frames(video_path, num_frames, sampling)
            if not imgs:
                raise RuntimeError("No frames extracted")
            caption = call_lmstudio_vision(imgs, system_prompt, model, prefill=prefill)

            if os.path.exists(out_txt) and prepend_existing:
                try:
                    with open(out_txt, "r", encoding="utf-8") as fh:
                        old = fh.read()
                except:
                    old = ""
                new_text = caption.strip() + ("\n\n" + old if old else "")
                with open(out_txt, "w", encoding="utf-8") as fh:
                    fh.write(new_text)
            else:
                with open(out_txt, "w", encoding="utf-8") as fh:
                    fh.write(caption.strip())

            results.append({"file": fn, "ok": True, "out": os.path.basename(out_txt)})
        except Exception as e:
            results.append({"file": fn, "ok": False, "error": str(e)})
    return jsonify({"count": len(results), "results": results})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5057, debug=True)
