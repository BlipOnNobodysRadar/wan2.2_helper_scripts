# WAN 2.2 Helper Scripts

A collection of small Bash utilities for preparing video datasets. Most scripts
rely on `ffmpeg`/`ffprobe`; some also require ImageMagick or Perl.

## Scripts

| Script | Description |
| --- | --- |
| `combineFirstLastImages.sh` | Combine first and last frame images into a single composite separated by a line. Requires ImageMagick. |
| `convert_to_16fps.sh` | Convert videos to constant 16 fps MP4 files. Customizable via env vars; optional GPU acceleration. |
| `convert_to_mp4.sh` | Batch convert animated GIF/WEBP and other video formats to MP4 with high-quality defaults and smart copy. |
| `extract_first_frames.sh` | Extract the first frame of each MP4 and create matching empty `.txt` files. |
| `extract_first-last_frames.sh` | Extract first and last frames (with fallbacks for reliable last-frame capture) and create accompanying `.txt` files. |
| `grab_5_frames.sh` | Grab five evenly spaced frames from a single video file. |
| `merge_lastframe_into_main.sh` | Merge caption text from `_lastFrame.txt` files into the main caption files, normalizing spacing. |
| `lmstudio_captioner` | Local web app that captions videos via LM Studio's API. Assistant prefill only appears as a separate pretend reply due to LM Studio API limits; load a model in LM Studio, enable the API in the Developer tab, and paste the model name into the app. |
| `multi_video_sync_compare.html` | Browser-based tool for loading multiple videos, adjusting per-video offsets, and keeping playback synchronized for side-by-side comparison. |

## License

MIT – see [LICENSE](LICENSE).
