---
name: reference-mp4-concat-audio-gap-drift
description: "Stream-copy concat of per-sentence clips whose audio is shorter than the video makes narration run AHEAD of the picture, cumulatively. Pad audio with apad=whole_dur."
metadata:
  node_type: memory
  type: reference
  originSessionId: 87fb8af5-38c0-40da-8437-49fc39802b1c
  modified: 2026-09-25T00:35:42.587Z
---

An MP4 audio track can't hold a gap. If a clip's pause exists only as extra video frames (the audio is shorter than the video), it plays fine alone. After an ffmpeg concat-demuxer `-c copy` join, though, players butt each sentence against the next one, so the narration drifts ahead of the slides by the sum of the pauses.

Seen 2026-09-24 in the Speedy "Why Speedy" intro:
- 52 clips, 21.3 s of drift; the user noticed it by lap 2.
- The final file's audio duration still looked normal. **Don't trust container durations as a check.**

**Fix:** pad the audio in every clip to the clip's full length:
`-af apad=whole_dur=<frames/FPS>` together with `-frames:v <frames>`.
After the fix, measured drift was 0.00 s. This is in `build_intro.py` `still()`.

**Check:** sum `ffprobe` stream durations of `v:0` minus `a:0` over the concat list; the total must be about 0. Cross-check with `silencedetect`: speech should restart just after each clip's start time.

Related: [[project_speedy_demo_diagrams]].
