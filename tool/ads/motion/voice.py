"""Voice-over for a motion ad, one file per line, with measured lengths.

Kokoro (Apache 2.0, commercial use allowed) runs locally. Lines are voiced
separately so picture and sound can be placed on exact frames; the timeline
(when each line starts, with the pause after it) is written next to the spec.

  KOKORO_DIR=<folder with kokoro-v1.0.onnx and voices-v1.0.bin> \
  python voice.py src/sound/Measured.json

Reads   spec["voice"] = {"name": "af_heart", "speed": 0.95, "lead": 0.4,
                         "lines": [{"id": "...", "text": "...", "pause": 0.3}]}
Writes  public/vo/<Id>/<id>.wav and src/sound/<Id>.timeline.json
"""

import json
import os
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

FPS = 30


def trim(audio, sr, floor=0.012):
    """Cut leading/trailing silence so a line starts on its frame."""
    loud = np.flatnonzero(np.abs(audio) > floor)
    if not len(loud):
        return audio
    pad = int(0.03 * sr)
    return audio[max(0, loud[0] - pad): loud[-1] + pad]


def main():
    spec_path = Path(sys.argv[1])
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    ad = spec_path.stem
    v = spec["voice"]
    model_dir = Path(os.environ.get("KOKORO_DIR", "."))
    kokoro = Kokoro(str(model_dir / "kokoro-v1.0.onnx"), str(model_dir / "voices-v1.0.bin"))
    out = Path(__file__).parent / "public" / "vo" / ad
    out.mkdir(parents=True, exist_ok=True)

    t = v.get("lead", 0.4)
    timeline = {}
    for line in v["lines"]:
        audio, sr = kokoro.create(line["text"], voice=line.get("voice", v["name"]), speed=line.get("speed", v.get("speed", 1.0)), lang="en-us")
        audio = trim(np.asarray(audio, dtype=np.float32), sr)
        sf.write(out / f"{line['id']}.wav", audio, sr)
        dur = len(audio) / sr
        timeline[line["id"]] = {"at": round(t * FPS), "end": round((t + dur) * FPS), "seconds": round(t, 3), "file": f"vo/{ad}/{line['id']}.wav"}
        print(f"{line['id']:>10}  {t:6.2f}s  {dur:5.2f}s  {line['text']}")
        t += dur + line.get("pause", 0.3)
    timeline["_end"] = {"at": round(t * FPS)}
    (spec_path.parent / f"{ad}.timeline.json").write_text(json.dumps(timeline, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
