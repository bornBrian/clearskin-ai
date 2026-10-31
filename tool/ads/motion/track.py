"""Tracks a face through a footage clip, for a live scan overlay.

Runs Google MediaPipe's face landmarker on every frame and keeps the points
ML Kit's face contours use in the app (outline, brows, eyes, lips, nose,
cheeks), triangulated once the way lib/domain/scan/face_mesh.dart does:
Delaunay, kept inside the face outline. So the overlay is the app's own
mesh, following a real face as it moves.

  MP_MODEL=<face_landmarker.task> python track.py public/footage/scan.mp4 public/track/scan.json

Writes {"aspect", "tris", "frames": [[[x, y], ...] | null per frame]} in
0..1 frame coordinates.
"""

import json
import os
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision
from scipy.spatial import Delaunay

# MediaPipe indexes for ML Kit's contours, in ML Kit's order.
CONTOURS = {
    'face': [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377,
             152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109],
    'leftEyebrowTop': [336, 296, 334, 293, 300],
    'leftEyebrowBottom': [285, 295, 282, 283, 276],
    'rightEyebrowTop': [70, 63, 105, 66, 107],
    'rightEyebrowBottom': [46, 53, 52, 65, 55],
    'leftEye': [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466],
    'rightEye': [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246],
    'upperLipTop': [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291],
    'upperLipBottom': [191, 80, 81, 82, 13, 312, 311, 310, 415],
    'lowerLipTop': [95, 88, 178, 87, 14, 317, 402, 318, 324],
    'lowerLipBottom': [146, 91, 181, 84, 17, 314, 405, 321, 375],
    'noseBridge': [168, 4],
    'noseBottom': [98, 2, 327],
    'leftCheek': [425],
    'rightCheek': [205],
}
IDX = [i for c in CONTOURS.values() for i in c]


def inside(poly, p):
    """Even-odd point-in-polygon."""
    x, y = p
    hit = False
    for (x1, y1), (x2, y2) in zip(poly, np.roll(poly, -1, axis=0)):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def main():
    src, out = sys.argv[1], Path(sys.argv[2])
    model = os.environ.get('MP_MODEL', str(Path.home() / '.clearskin/mediapipe/face_landmarker.task'))
    landmarker = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=model),
        running_mode=vision.RunningMode.VIDEO, num_faces=1,
        min_face_detection_confidence=0.5, min_tracking_confidence=0.5))
    cap = cv2.VideoCapture(src)
    fps = cap.get(cv2.CAP_PROP_FPS)
    w, h = cap.get(cv2.CAP_PROP_FRAME_WIDTH), cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    frames, k = [], 0
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        img = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        r = landmarker.detect_for_video(img, int(k * 1000 / fps))
        frames.append([[lm[i].x, lm[i].y] for i in IDX] if (lm := (r.face_landmarks or [None])[0]) else None)
        k += 1

    # Triangulate on the median face, in true proportions, like the app.
    found = np.array([f for f in frames if f])
    med = np.median(found, axis=0) * [w / h, 1]
    outline = med[:len(CONTOURS['face'])]
    face_w = outline[:, 0].max() - outline[:, 0].min()
    tris = []
    for t in Delaunay(med).simplices:
        a, b, c = med[t]
        longest = max(np.linalg.norm(a - b), np.linalg.norm(b - c), np.linalg.norm(c - a))
        if longest < face_w * 0.35 and inside(outline, (a + b + c) / 3):
            tris.append([int(i) for i in t])

    out.parent.mkdir(parents=True, exist_ok=True)
    rnd = lambda f: [[round(x, 5), round(y, 5)] for x, y in f] if f else None
    out.write_text(json.dumps({'aspect': w / h, 'tris': tris, 'frames': [rnd(f) for f in frames]}))
    print(f'{out}: {len(frames)} frames, face in {len(found)}, {len(IDX)} points, {len(tris)} triangles')


if __name__ == '__main__':
    main()
