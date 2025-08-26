
#!/usr/bin/env bash
# merge_lastframe_into_main.sh
set -euo pipefail
shopt -s nullglob nocaseglob

# Requires: perl (for whole-file regex & newline normalization)
command -v perl >/dev/null 2>&1 || { echo "Missing: perl"; exit 1; }

for lf in *_lastFrame.txt; do
  base="${lf%_lastFrame.txt}"
  main="${base}.txt"

  if [[ ! -e "$main" ]]; then
    echo "SKIP  no main caption for: $base (expected $main)"
    continue
  fi

  # Normalize newlines so we can guarantee exactly one blank line between blocks
  tmp_main="$(mktemp)"
  tmp_lf="$(mktemp)"

  # Strip trailing newlines from main; strip leading newlines from lastFrame
  perl -0777 -pe 's/\n+\z//s' "$main" > "$tmp_main"
  perl -0777 -pe 's/\A\n+//s' "$lf"   > "$tmp_lf"

  # Build merged content
  merged="$(mktemp)"
  if [[ -s "$tmp_main" && -s "$tmp_lf" ]]; then
    cat "$tmp_main" > "$merged"
    printf '\n\n' >> "$merged"        # exactly one blank line between non-empty parts
    cat "$tmp_lf" >> "$merged"
  elif [[ -s "$tmp_main" ]]; then
    cat "$tmp_main" > "$merged"
  else
    # main was empty -> just use lastFrame content (no leading blank lines)
    cat "$tmp_lf" > "$merged"
  fi

  # Replace the first instance of ", " in the merged file with two newlines
  fixed="$(mktemp)"
  perl -0777 -pe 's/, /\n\n/' "$merged" > "$fixed"

  # Overwrite the main file
  mv -f "$fixed" "$main"
  rm -f "$merged" "$tmp_main" "$tmp_lf"

  echo "MERGED → $main  (+$lf)"
done
