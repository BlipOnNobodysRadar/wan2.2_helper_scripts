#!/usr/bin/env bash
# TL;DR slap this in a directory with animated gifs, animated webps, and non-mp4 video files you want to convert into .mp4 files. Then run it, converts all to mp4.
# Extended: convert_webp_to_mp4.sh (patched)
# - Robust GIF/WEBP → MP4 conversion. WEBP uses ImageMagick path by default.
# - General video → MP4 with smart-copy option.
# - High-quality x264 defaults.
# - If no inputs/dirs, runs on the script's directory (NON-RECURSIVE).

set -euo pipefail
shopt -s nullglob

# ---------- resolve script directory (handles symlinks) ----------
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# ---------- defaults ----------
CRF="${CRF:-14}"
PRESET="${PRESET:-slow}"
BG="${BG:-white}"
OUTDIR="${OUTDIR:-converted}"
MIN_CS="${MIN_CS:-10}"
AUDIO_KBPS="${AUDIO_KBPS:-320}"
OVERWRITE=0
SMART_COPY=0
LOSSLESS=0
FPS=""

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need ffmpeg
need ffprobe

have_magick() { command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; }

VIDEO_EXTS=(webm avi mkv mov m4v flv ts mts m2ts mpg mpeg 3gp ogv mxf wmv mp4)
ANIM_EXTS=(webp gif)

usage() { sed -n '1,120p' "$0"; }

# ---------- parse CLI ----------
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --overwrite) OVERWRITE=1; shift;;
    --smart-copy) SMART_COPY=1; shift;;
    --lossless) LOSSLESS=1; shift;;
    --fps)      FPS="${2:-}"; shift 2;;
    --crf)      CRF="${2:-}"; shift 2;;
    --preset)   PRESET="${2:-}"; shift 2;;
    --audio-bitrate) AUDIO_KBPS="${2:-}"; shift 2;;
    --bg)       BG="${2:-}"; shift 2;;
    --outdir)   OUTDIR="${2:-}"; shift 2;;
    -h|--help)  usage; exit 0;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1;;
    *)  ARGS+=("$1"); shift;;
  esac
done

# ---------- default input ----------
if [[ ${#ARGS[@]} -eq 0 ]]; then
  echo "No inputs provided; defaulting to script directory: $SCRIPT_DIR"
  cd "$SCRIPT_DIR"
  ARGS=(".")
fi

mkdir -p -- "$OUTDIR"

FF_OW="-n"; [[ $OVERWRITE -eq 1 ]] && FF_OW="-y"

x264_args=(-c:v libx264 -preset "$PRESET")
if [[ $LOSSLESS -eq 1 ]]; then x264_args+=(-crf 0); else x264_args+=(-crf "$CRF"); fi
audio_args=(-c:a aac -b:a "${AUDIO_KBPS}k")
common_tail=(-movflags +faststart -pix_fmt yuv420p)

fps_vf=""; fps_in=()
if [[ -n "$FPS" ]]; then
  fps_vf=",fps=${FPS}"
  fps_in=(-r "$FPS")
fi

lc_ext() { printf '%s\n' "${1##*.}" | tr '[:upper:]' '[:lower:]'; }

is_in_list() {
  local needle="$1"; shift
  local e
  for e in "$@"; do [[ "$needle" == "$e" ]] && return 0; done
  return 1
}

should_smart_copy() {
  local in="$1" v a p
  v=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$in" 2>/dev/null | head -n1 || true)
  a=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$in" 2>/dev/null | head -n1 || true)
  p=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=nw=1:nk=1 "$in" 2>/dev/null | head -n1 || true)
  [[ "$v" =~ ^(h264|avc1)$ ]] && { [[ -z "$a" || "$a" == "aac" ]]; } && [[ "$p" == "yuv420p" ]]
}

# ---------- animated helpers ----------
anim_ffmpeg_encode() {
  local in="$1" out="$2"
  local tmp; tmp="$(mktemp --suffix=.mp4)"
  if ffmpeg -hide_banner -loglevel error -y -i "$in" \
       "${x264_args[@]}" -an \
       -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2${fps_vf}" \
       "${common_tail[@]}" "$tmp"; then
    if [[ -e "$out" && $OVERWRITE -eq 0 ]]; then
      echo "• output exists, skipping (use --overwrite to replace): $out"
      rm -f -- "$tmp"; return 0
    fi
    mv -f -- "$tmp" "$out"; return 0
  fi
  rm -f -- "$tmp"; return 1
}

sanitize_with_exiftool_and_try() {
  local in="$1" out="$2"
  command -v exiftool >/dev/null 2>&1 || return 1

  local tmpd; tmpd="$(mktemp -d)"
  # Trap is self-removing and guarded for set -u
  trap 'if [[ -n "${tmpd:-}" && -d "$tmpd" ]]; then rm -rf -- "$tmpd"; fi; trap - RETURN' RETURN

  local ext="${in##*.}"
  cp -- "$in" "$tmpd/in.$ext"
  exiftool -overwrite_original -all= "$tmpd/in.$ext" >/dev/null 2>&1 || return 1

  local tmpout; tmpout="$(mktemp --suffix=.mp4)"
  if ffmpeg -hide_banner -loglevel error -y -i "$tmpd/in.$ext" \
       "${x264_args[@]}" -an \
       -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2${fps_vf}" \
       "${common_tail[@]}" "$tmpout"; then
    if [[ -e "$out" && $OVERWRITE -eq 0 ]]; then
      echo "• output exists, skipping (use --overwrite to replace): $out"
      rm -f -- "$tmpout"; return 0
    fi
    mv -f -- "$tmpout" "$out"; return 0
  fi
  rm -f -- "$tmpout"; return 1
}

fallback_imagemagick_vfr() {
  local in="$1" out="$2"
  local IM
  if command -v magick >/dev/null 2>&1; then IM="magick"
  elif command -v convert >/dev/null 2>&1; then IM="convert"
  else echo "ImageMagick not found (need 'magick' or 'convert')"; return 1
  fi

  local tmpd; tmpd="$(mktemp -d)"
  # FIX: no global cleanup() function; guarded, self-removing RETURN trap
  trap 'if [[ -n "${tmpd:-}" && -d "$tmpd" ]]; then rm -rf -- "$tmpd"; fi; trap - RETURN' RETURN

  "$IM" "$in" -coalesce -background "$BG" -alpha remove -alpha off \
        "$tmpd/%06d.png" 2>/dev/null || true

  local nframes
  nframes=$(ls -1 "$tmpd"/*.png 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$nframes" -eq 0 ]]; then
    echo "Fallback decode produced no frames."
    return 1
  fi

  local -a delays=()
  mapfile -t delays < <($IM identify -format "%T\n" "$in" 2>/dev/null || true)
  if [[ "${#delays[@]}" -ne "$nframes" ]]; then
    while [[ "${#delays[@]}" -lt "$nframes" ]]; do delays+=("$MIN_CS"); done
    if [[ "${#delays[@]}" -gt "$nframes" ]]; then delays=("${delays[@]:0:$nframes}"); fi
  fi

  local tmpout; tmpout="$(mktemp --suffix=.mp4)"
  if [[ "${#delays[@]}" -eq 0 ]]; then
    if ffmpeg -hide_banner -loglevel error -y \
         -framerate 30 -i "$tmpd/%06d.png" \
         "${x264_args[@]}" -an \
         -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
         "${common_tail[@]}" "$tmpout"; then
      if [[ -e "$out" && $OVERWRITE -eq 0 ]]; then
        echo "• output exists, skipping (use --overwrite to replace): $out"
        rm -f -- "$tmpout"; return 0
      fi
      mv -f -- "$tmpout" "$out"; return 0
    fi
    rm -f -- "$tmpout"; return 1
  fi

  local list="$tmpd/list.txt"
  {
    echo "ffconcat version 1.0"
    local i=0
    while [[ $i -lt $nframes ]]; do
      local frame; frame=$(printf "%06d.png" "$i")
      local cs="${delays[$i]}"; [[ -z "$cs" || "$cs" -lt 1 ]] && cs="$MIN_CS"
      local dur; dur=$(awk -v cs="$cs" 'BEGIN{ printf "%.6f", cs/100.0 }')
      echo "file '$tmpd/$frame'"
      echo "duration $dur"
      ((i++))
    done
    echo "file '$tmpd/$(printf "%06d.png" $((nframes-1)))'"
  } > "$list"

  if ffmpeg -hide_banner -loglevel error -y -safe 0 -f concat -i "$list" \
       "${x264_args[@]}" -an \
       -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
       "${common_tail[@]}" "$tmpout"; then
    if [[ -e "$out" && $OVERWRITE -eq 0 ]]; then
      echo "• output exists, skipping (use --overwrite to replace): $out"
      rm -f -- "$tmpout"; return 0
    fi
    mv -f -- "$tmpout" "$out"; return 0
  fi
  rm -f -- "$tmpout"; return 1
}

convert_anim() {
  local in="$1" rel out_dir out dname ext
  rel="$(realpath --relative-to="." "$in" 2>/dev/null || echo "$in")"
  dname="$(dirname -- "$rel")"
  if [[ "$dname" == "." ]]; then out_dir="$OUTDIR"; else out_dir="$OUTDIR/$dname"; fi
  mkdir -p -- "$out_dir"
  out="$out_dir/$(basename -- "${in%.*}").mp4"
  ext="$(lc_ext "$in")"

  if [[ -e "$out" && $OVERWRITE -eq 0 ]]; then
    echo "• already exists, skipping: $out"
    return 0
  fi

  # Route WEBP through ImageMagick by default (more robust)
  if [[ "$ext" == "webp" ]]; then
    echo "→ [anim:webp→IM] $in → $out"
    if fallback_imagemagick_vfr "$in" "$out"; then
      echo "✓ webp via ImageMagick: $out"; return 0
    fi
    echo "✗ webp via ImageMagick failed on $in"; return 1
  fi

  echo "→ [anim] $in → $out"
  if anim_ffmpeg_encode "$in" "$out"; then
    echo "✓ ffmpeg: $out"; return 0
  fi

  echo "… direct ffmpeg failed; trying EXIF clean + retry"
  if sanitize_with_exiftool_and_try "$in" "$out"; then
    echo "✓ exiftool cleaned: $out"; return 0
  fi

  echo "… EXIF clean failed; using ImageMagick variable-framerate fallback"
  if fallback_imagemagick_vfr "$in" "$out"; then
    echo "✓ fallback (VFR): $out"; return 0
  fi

  echo "✗ failed on $in"; return 1
}

convert_video() {
  local in="$1" rel out_dir out dname
  rel="$(realpath --relative-to="." "$in" 2>/dev/null || echo "$in")"
  dname="$(dirname -- "$rel")"
  if [[ "$dname" == "." ]]; then out_dir="$OUTDIR"; else out_dir="$OUTDIR/$dname"; fi
  mkdir -p -- "$out_dir"
  out="$out_dir/$(basename -- "${in%.*}").mp4"

  if [[ "${in,,}" == *.mp4 && $OVERWRITE -eq 0 ]]; then
    echo "• already mp4, skipping: $in"; return 0
  fi

  if [[ $SMART_COPY -eq 1 ]] && should_smart_copy "$in"; then
    echo "→ [remux] $in → $out"
    if ffmpeg -hide_banner -loglevel warning $FF_OW -i "$in" -c:v copy -c:a copy -movflags +faststart "${fps_in[@]}" "$out"; then
      echo "✓ wrote $out (remux)"; return 0
    fi
    echo "… remux failed; falling back to re-encode"
  fi

  echo "→ [re-encode] $in → $out"
  if ffmpeg -hide_banner -loglevel warning $FF_OW -i "$in" "${x264_args[@]}" "${audio_args[@]}" \
       -filter:v "scale=trunc(iw/2)*2:trunc(ih/2)*2${fps_vf}" "${common_tail[@]}" "$out"; then
    echo "✓ wrote $out"; return 0
  fi
  echo "✗ failed on $in"; return 1
}

gather_inputs() {
  local p
  local all_exts=("${VIDEO_EXTS[@]}" "${ANIM_EXTS[@]}")
  local rx_exts
  rx_exts="$(printf '%s|' "${all_exts[@]}" | sed 's/|$//')"
  for p in "$@"; do
    if [[ -d "$p" ]]; then
      find "$p" -maxdepth 1 -type f -regextype posix-extended -iregex ".*\.(${rx_exts})" -print0
    elif [[ -f "$p" ]]; then
      printf '%s\0' "$p"
    else
      echo "Skipping non-existent path: $p" >&2
    fi
  done
}

fails=0
mapfile -d '' -t INPUTS < <(gather_inputs "${ARGS[@]}") || { echo "File discovery failed."; exit 1; }

for f in "${INPUTS[@]}"; do
  ext="$(lc_ext "$f")"
  if is_in_list "$ext" "${ANIM_EXTS[@]}"; then
    convert_anim "$f" || ((fails++))
  else
    convert_video "$f" || ((fails++))
  fi
done

if [[ $fails -gt 0 ]]; then
  echo "Completed with $fails failure(s)."
  exit 1
fi
echo "All done."
