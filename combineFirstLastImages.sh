#!/usr/bin/env bash
# Combine the first and last frame images into a single side-by-side
# composite separated by a line. Requires ImageMagick (magick or
# convert/identify).
set -euo pipefail
shopt -s nullglob nocaseglob

# Tunables via env vars:
#   IMG_EXT=jpg OUTDIR="pairs" SEP=2 PAD=6 SPACE_COLOR="white" FORCE=0
IMG_EXT="${IMG_EXT:-jpg}"           # first/last images extension
OUTDIR="${OUTDIR:-pairs}"           # output directory
SEP="${SEP:-2}"                     # black line thickness (pixels)
PAD="${PAD:-6}"                     # blank padding above & below the black line
SPACE_COLOR="${SPACE_COLOR:-white}" # color of the blank padding & side padding
FORCE="${FORCE:-0}"                 # 1 to overwrite existing outputs

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

# Pick ImageMagick v7 ("magick") if present; otherwise fall back to v6 ("convert"/"identify")
if command -v magick >/dev/null 2>&1; then
  IM="magick"
  IDENT="magick identify"
else
  need convert
  need identify
  IM="convert"
  IDENT="identify"
fi

mkdir -p "$OUTDIR"

combined=0
skipped=0

for first in *."$IMG_EXT"; do
  # Skip files that are already "_lastFrame"
  [[ "$first" == *_lastFrame."$IMG_EXT" ]] && continue

  stem="${first%."$IMG_EXT"}"
  last="${stem}_lastFrame.${IMG_EXT}"
  [[ -e "$last" ]] || { echo "SKIP  no last frame for: $stem"; ((skipped++)); continue; }

  out="${OUTDIR}/${stem}_first_last.${IMG_EXT}"
  if [[ -e "$out" && "$FORCE" -ne 1 ]]; then
    echo "SKIP  exists: $out (set FORCE=1 to overwrite)"
    ((skipped++))
    continue
  fi

  # Get dimensions
  read -r w1 h1 < <($IDENT -format "%w %h" "$first")
  read -r w2 h2 < <($IDENT -format "%w %h" "$last")
  W=$(( w1 > w2 ? w1 : w2 ))
  H1="$h1"
  H2="$h2"

  # Pad each image to the same width, centered
  tmp1="$(mktemp)"; tmp2="$(mktemp)"; spacer="$(mktemp)"
  cleanup() { rm -f "$tmp1" "$tmp2" "$spacer"; }
  trap cleanup EXIT

  "$IM" "$first" -background "$SPACE_COLOR" -gravity center -extent "${W}x${H1}" "$tmp1"
  "$IM" "$last"  -background "$SPACE_COLOR" -gravity center -extent "${W}x${H2}" "$tmp2"

  # Build a spacer: total height = 2*PAD + SEP, with a black bar centered
  total_h=$(( 2*PAD + SEP ))
  "$IM" -size "${W}x${total_h}" "xc:${SPACE_COLOR}" \
        -fill black -draw "rectangle 0,${PAD} $((W-1)),$((PAD+SEP-1))" \
        "$spacer"

  # Stack first + spacer + last
  "$IM" "$tmp1" "$spacer" "$tmp2" -append -strip "$out"

  cleanup
  trap - EXIT

  echo "MADE  $out"
  ((combined++))
done

echo "Done. Combined: $combined  |  Skipped: $skipped"
