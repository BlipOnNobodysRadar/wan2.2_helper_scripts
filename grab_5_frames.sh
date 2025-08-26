
#!/usr/bin/env bash
# grab_5_frames.sh
# Extract 5 evenly-distributed frames from a video using ffmpeg/ffprobe.
# Output files: <input_basename>_frame1.jpg ... _frame5.jpg (in the same folder)

set -euo pipefail

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "This script requires ffmpeg and ffprobe. Please install them and retry." >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/video.(mp4|mkv|webm|mov|avi|m4v)"
  exit 1
fi

in="$1"
if [[ ! -f "$in" ]]; then
  echo "Input not found: $in" >&2
  exit 1
fi

# Get duration in seconds (floating)
duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 -- "$in" 2>/dev/null || true)"
if [[ -z "${duration:-}" || "$duration" == "N/A" ]]; then
  # Fallback to stream duration if format duration is missing
  duration="$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 -- "$in" 2>/dev/null || true)"
fi
if [[ -z "${duration:-}" || "$duration" == "N/A" ]]; then
  echo "Could not determine video duration for: $in" >&2
  exit 1
fi

# Strip extension for output base
filename="$(basename -- "$in")"
dirpath="$(dirname -- "$in")"
base="${filename%.*}"

# We’ll sample at i/(N+1) to avoid the very first/last frames
N=5

for i in $(seq 1 $N); do
  # Timestamp in seconds with millisecond precision
  ts="$(awk -v d="$duration" -v i="$i" -v n="$N" 'BEGIN { printf("%.3f", d * (i/(n+1))) }')"
  out="$dirpath/${base}_frame${i}.jpg"

  # -ss before -i = fast seek; then grab exactly 1 frame
  ffmpeg -hide_banner -loglevel error -y -ss "$ts" -i "$in" -frames:v 1 -q:v 2 "$out"

  echo "✓ Wrote $out at t=${ts}s"
done

echo "Done."
