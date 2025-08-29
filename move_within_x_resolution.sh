
#!/usr/bin/env bash
# move_within_x_resolution.sh
# Move MP4s whose avg dimension ( (W+H)/2 ) is <= X into ./within_X_resolution/
#
# Env:
#   X=512            # threshold; files with avg_dim <= X are moved
#   DRYRUN=0         # 1 = show actions only
#   OVERWRITE=0      # 1 = force overwrite if dest exists
#
# Current directory only (simple).

set -euo pipefail
shopt -s nullglob nocaseglob

X="${X:-512}"
DRYRUN="${DRYRUN:-0}"
OVERWRITE="${OVERWRITE:-0}"
DEST="within_${X}_resolution"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need ffprobe; need mv

mkdir -p "$DEST"
ffw_mv=(-n); [[ "$OVERWRITE" == "1" ]] && ffw_mv=(-f)

avg_dim_of() {
  local f="$1" wh w h
  wh="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
        -of csv=p=0:s=x "$f" 2>/dev/null | head -n1 | tr -d '\r')"
  [[ -z "$wh" ]] && { echo ""; return 1; }
  w="${wh%x*}"; h="${wh#*x}"
  awk -v w="$w" -v h="$h" 'BEGIN{printf "%.0f", (w + h)/2.0}'
}

processed=0 moved=0 kept=0 warned=0

for f in *.mp4; do
  [[ -e "$f" ]] || continue
  ((processed++)) || true
  ad="$(avg_dim_of "$f" || echo "")"
  if ! [[ "$ad" =~ ^[0-9]+$ ]]; then
    echo "WARN  $f: could not read resolution — skipping"; ((warned++)) || true; continue
  fi

  if (( ad <= X )); then
    echo "MOVE  $f  (avg_dim=$ad <= $X) -> $DEST/"
    if [[ "$DRYRUN" != "1" ]]; then
      mv "${ffw_mv[@]}" -- "$f" "$DEST/"
    fi
    ((moved++)) || true
  else
    echo "KEEP  $f  (avg_dim=$ad > $X)"
    ((kept++)) || true
  fi
done

echo "Done. processed=$processed moved=$moved kept=$kept warned=$warned dest=$DEST"

# Note:
# - Uses encoded width/height, not display-rotation metadata.
