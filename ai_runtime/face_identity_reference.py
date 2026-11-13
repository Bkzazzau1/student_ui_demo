"""Reference implementation of the K-SLAS face identity pipeline.

The app computes face embeddings on the device. The school system needs the
same computation to rebuild official templates from approved registration
photos (and to rebuild every template after a model upgrade), and the
calibration tool needs it to score volunteer data. This module is that
reference, written with numpy only so it runs anywhere ONNX Runtime does.

It must stay numerically equivalent to the app:

* face box: YuNet (OpenCV Zoo, 640x640 input, BGR 0..255) on the frame;
* landmarks: the MediaPipe face mesh on a square crop 1.5x the face box
  (nearest resize to 256x256, RGB / 255), as in
  ``windows/runner/face_landmarker_runtime_channel.cpp``;
* alignment: least-squares similarity from five landmarks to the ArcFace
  template, bilinear sampling (``FaceAlignment`` in Dart);
* embedding: SFace with raw RGB 0..255 input - the model normalizes
  internally (``(x - 127.5) * 0.0078125``).

``tests/test_face_identity_reference.py`` and the Dart test
``test/face_alignment_test.dart`` share golden fixtures to keep them aligned.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np

PREPROCESSING_VERSION = "sface-5pt-ls-bilinear-rgb255-v2"

#: ArcFace 112x112 reference positions: eye centres, nose tip, mouth corners.
ARCFACE_TEMPLATE = np.array(
    [
        [38.2946, 51.6963],
        [73.5318, 51.5014],
        [56.0252, 71.7366],
        [41.5493, 92.3655],
        [70.7299, 92.2041],
    ],
    dtype=np.float64,
)

#: MediaPipe face-mesh indices: eye corners (image-left eye, image-right
#: eye), nose tip, mouth corners.
LEFT_EYE_CORNERS = (33, 133)
RIGHT_EYE_CORNERS = (362, 263)
NOSE_TIP = 1
MOUTH_LEFT = 61
MOUTH_RIGHT = 291

MESH_SIDE = 256
#: The landmark crop is this many times the larger side of the face box.
CROP_SCALE = 1.5
ALIGNED_SIDE = 112

#: Minimum face-presence probability from the mesh (sigmoid of its rank-4
#: scalar output), matching the app's minimum face confidence.
MIN_FACE_PRESENCE = 0.6

YUNET_SIDE = 640
YUNET_STRIDES = (8, 16, 32)
YUNET_SCORE_THRESHOLD = 0.6
YUNET_NMS_IOU = 0.3


@dataclass(frozen=True)
class FaceBox:
    x: float
    y: float
    width: float
    height: float
    score: float
    keypoints: np.ndarray  # (5, 2): right eye, left eye, nose, mouth corners

    @property
    def area(self) -> float:
        return self.width * self.height


def yunet_input(rgb: np.ndarray) -> tuple[np.ndarray, float]:
    """Nearest-neighbour downscale (never upscale) so the longer side fits
    640, padded with black at the bottom/right; BGR 0..255, NCHW."""
    height, width = rgb.shape[:2]
    scale = min(1.0, YUNET_SIDE / max(height, width))
    out_w = max(1, int(width * scale))
    out_h = max(1, int(height * scale))
    ys = np.minimum(height - 1, (np.arange(out_h) * height) // out_h)
    xs = np.minimum(width - 1, (np.arange(out_w) * width) // out_w)
    canvas = np.zeros((YUNET_SIDE, YUNET_SIDE, 3), dtype=np.float32)
    canvas[:out_h, :out_w] = rgb[ys][:, xs][:, :, ::-1]
    return np.ascontiguousarray(canvas.transpose(2, 0, 1))[None], scale


def yunet_decode(outputs: dict[str, np.ndarray], scale: float) -> list[FaceBox]:
    """Decodes YuNet 2023mar outputs (as OpenCV's FaceDetectorYN does) and
    applies non-maximum suppression. Coordinates are in source pixels."""
    scores, boxes, keypoints = [], [], []
    for stride in YUNET_STRIDES:
        cls = np.clip(outputs[f"cls_{stride}"].reshape(-1).astype(np.float64), 0, 1)
        obj = np.clip(outputs[f"obj_{stride}"].reshape(-1).astype(np.float64), 0, 1)
        bbox = outputs[f"bbox_{stride}"].reshape(-1, 4).astype(np.float64)
        kps = outputs[f"kps_{stride}"].reshape(-1, 10).astype(np.float64)
        score = np.sqrt(cls * obj)
        index = np.nonzero(score >= YUNET_SCORE_THRESHOLD)[0]
        if index.size == 0:
            continue
        cols = YUNET_SIDE // stride
        row, col = np.divmod(index, cols)
        cx = (col + bbox[index, 0]) * stride
        cy = (row + bbox[index, 1]) * stride
        w = np.exp(bbox[index, 2]) * stride
        h = np.exp(bbox[index, 3]) * stride
        boxes.append(np.stack([cx - w / 2, cy - h / 2, w, h], axis=1) / scale)
        points = np.empty((index.size, 5, 2), dtype=np.float64)
        points[:, :, 0] = (kps[index][:, 0::2] + col[:, None]) * stride / scale
        points[:, :, 1] = (kps[index][:, 1::2] + row[:, None]) * stride / scale
        keypoints.append(points)
        scores.append(score[index])
    if not scores:
        return []
    score = np.concatenate(scores)
    box = np.concatenate(boxes)
    points = np.concatenate(keypoints)
    # Greedy NMS in score order (stable, like the native std::stable_sort).
    order = np.argsort(-score, kind="stable")
    x0, y0 = box[:, 0], box[:, 1]
    x1, y1 = x0 + box[:, 2], y0 + box[:, 3]
    area = box[:, 2] * box[:, 3]
    suppressed = np.zeros(score.size, dtype=bool)
    kept: list[FaceBox] = []
    for i in order:
        if suppressed[i]:
            continue
        kept.append(
            FaceBox(
                x=float(box[i, 0]),
                y=float(box[i, 1]),
                width=float(box[i, 2]),
                height=float(box[i, 3]),
                score=float(score[i]),
                keypoints=points[i],
            )
        )
        inter = np.clip(np.minimum(x1, x1[i]) - np.maximum(x0, x0[i]), 0, None) * np.clip(
            np.minimum(y1, y1[i]) - np.maximum(y0, y0[i]), 0, None
        )
        union = area + area[i] - inter
        iou = np.divide(inter, union, out=np.zeros_like(inter), where=union > 0)
        suppressed |= iou > YUNET_NMS_IOU
    return kept


def face_crop_window(face: FaceBox, scale: float = CROP_SCALE) -> tuple[int, int, int]:
    """Square landmark crop (left, top, side) centred on the face box."""
    side = max(16, int(round(max(face.width, face.height) * scale)))
    left = int(round(face.x + face.width / 2 - side / 2))
    top = int(round(face.y + face.height / 2 - side / 2))
    return left, top, side


def mesh_input(rgb: np.ndarray, side: int = MESH_SIDE) -> np.ndarray:
    """Nearest-neighbour resize to ``side`` x ``side``, scaled to 0..1, NHWC."""
    height, width = rgb.shape[:2]
    ys = np.minimum(height - 1, (np.arange(side) * height) // side)
    xs = np.minimum(width - 1, (np.arange(side) * width) // side)
    return (rgb[ys][:, xs].astype(np.float32) / 255.0)[None]


def square_crop(rgb: np.ndarray, left: int, top: int, side: int) -> np.ndarray:
    """Crop a square that may extend past the image; outside is black."""
    height, width = rgb.shape[:2]
    crop = np.zeros((side, side, 3), dtype=np.uint8)
    x0, y0 = max(0, left), max(0, top)
    x1, y1 = min(width, left + side), min(height, top + side)
    if x1 > x0 and y1 > y0:
        crop[y0 - top : y1 - top, x0 - left : x1 - left] = rgb[y0:y1, x0:x1]
    return crop


def five_points(points: np.ndarray) -> np.ndarray:
    left_eye = (points[LEFT_EYE_CORNERS[0]] + points[LEFT_EYE_CORNERS[1]]) / 2
    right_eye = (points[RIGHT_EYE_CORNERS[0]] + points[RIGHT_EYE_CORNERS[1]]) / 2
    return np.array(
        [left_eye, right_eye, points[NOSE_TIP], points[MOUTH_LEFT], points[MOUTH_RIGHT]],
        dtype=np.float64,
    )


def similarity_least_squares(src: np.ndarray, dst: np.ndarray) -> Optional[np.ndarray]:
    """2x3 matrix of the least-squares similarity (rotation, uniform scale,
    translation; never a reflection) that maps ``src`` onto ``dst``."""
    src = np.asarray(src, dtype=np.float64)
    dst = np.asarray(dst, dtype=np.float64)
    src_mean = src.mean(axis=0)
    dst_mean = dst.mean(axis=0)
    p = src - src_mean
    q = dst - dst_mean
    norm = float((p * p).sum())
    if norm < 1e-9:
        return None
    a = float((p[:, 0] * q[:, 0] + p[:, 1] * q[:, 1]).sum()) / norm
    b = float((p[:, 0] * q[:, 1] - p[:, 1] * q[:, 0]).sum()) / norm
    tx = dst_mean[0] - (a * src_mean[0] - b * src_mean[1])
    ty = dst_mean[1] - (b * src_mean[0] + a * src_mean[1])
    return np.array([[a, -b, tx], [b, a, ty]], dtype=np.float64)


def warp_bilinear(rgb: np.ndarray, matrix: np.ndarray, side: int = ALIGNED_SIDE) -> Optional[np.ndarray]:
    """Applies ``matrix`` (source -> output) with bilinear sampling. Pixels
    outside the source are black. Values round half up, as in Dart."""
    a, b = matrix[0, 0], matrix[1, 0]
    det = a * a + b * b
    if det < 1e-12:
        return None
    tx, ty = matrix[0, 2], matrix[1, 2]
    ys, xs = np.mgrid[0:side, 0:side].astype(np.float64)
    dx = xs - tx
    dy = ys - ty
    # Inverse of [[a, -b], [b, a]] is [[a, b], [-b, a]] / det.
    sx = (a * dx + b * dy) / det
    sy = (-b * dx + a * dy) / det
    x0 = np.floor(sx)
    y0 = np.floor(sy)
    fx = sx - x0
    fy = sy - y0
    x0 = x0.astype(np.int64)
    y0 = y0.astype(np.int64)
    height, width = rgb.shape[:2]
    source = rgb.astype(np.float64)

    def sample(yy: np.ndarray, xx: np.ndarray) -> np.ndarray:
        inside = (xx >= 0) & (xx < width) & (yy >= 0) & (yy < height)
        values = source[np.clip(yy, 0, height - 1), np.clip(xx, 0, width - 1)]
        return values * inside[..., None]

    top = sample(y0, x0) * (1 - fx)[..., None] + sample(y0, x0 + 1) * fx[..., None]
    bottom = sample(y0 + 1, x0) * (1 - fx)[..., None] + sample(y0 + 1, x0 + 1) * fx[..., None]
    value = top * (1 - fy)[..., None] + bottom * fy[..., None]
    return np.clip(np.floor(value + 0.5), 0, 255).astype(np.uint8)


def align_face(rgb: np.ndarray, points: np.ndarray) -> Optional[np.ndarray]:
    matrix = similarity_least_squares(five_points(points), ARCFACE_TEMPLATE)
    return None if matrix is None else warp_bilinear(rgb, matrix)


def embedding_input(aligned_rgb: np.ndarray) -> np.ndarray:
    """SFace input: RGB values 0..255, NCHW. The model normalizes itself."""
    return np.ascontiguousarray(aligned_rgb.astype(np.float32).transpose(2, 0, 1))[None]


def procedural_rgb(width: int, height: int) -> np.ndarray:
    """Deterministic test image shared with the Dart alignment test."""
    ys, xs = np.mgrid[0:height, 0:width].astype(np.int64)
    image = np.empty((height, width, 3), dtype=np.uint8)
    image[..., 0] = (xs * 7 + ys * 3) % 256
    image[..., 1] = (xs * 2 + ys * 5 + 40) % 256
    image[..., 2] = (xs * xs + ys * 11) % 256
    return image


#: Five face points (image-left eye, image-right eye, nose, mouth corners)
#: for the shared alignment fixture: a slightly rotated, off-centre face.
GOLDEN_POINTS = np.array(
    [[71.25, 64.5], [118.75, 60.25], [97.5, 92.0], [76.0, 118.5], [114.25, 115.75]],
    dtype=np.float64,
)
GOLDEN_IMAGE_SIZE = (200, 160)  # width, height


@dataclass
class FaceIdentityReference:
    """Runs the full pipeline with ONNX Runtime sessions."""

    detector_session: object
    landmark_session: object
    embedding_session: object

    @classmethod
    def from_repo(cls, repo: Path) -> "FaceIdentityReference":
        import onnxruntime as ort

        options = ort.SessionOptions()
        options.log_severity_level = 3
        providers = ["CPUExecutionProvider"]
        return cls(
            ort.InferenceSession(
                str(repo / "assets/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"),
                options,
                providers=providers,
            ),
            ort.InferenceSession(
                str(repo / "assets/models/face_landmarker_windows/face_landmarks.onnx"),
                options,
                providers=providers,
            ),
            ort.InferenceSession(
                str(repo / "assets/models/face_embedding_sface/face_recognition_sface_2021dec.onnx"),
                options,
                providers=providers,
            ),
        )

    def mesh_points(self, rgb: np.ndarray) -> Optional[np.ndarray]:
        name = self.landmark_session.get_inputs()[0].name
        outputs = self.landmark_session.run(None, {name: mesh_input(rgb)})
        raw = next((out for out in outputs if out.size in (478 * 3, 468 * 3)), None)
        if raw is None:
            return None
        logit = next((out for out in outputs if out.size == 1 and out.ndim == 4), None)
        if logit is not None and 1 / (1 + np.exp(-float(logit.reshape(-1)[0]))) < MIN_FACE_PRESENCE:
            return None
        points = raw.reshape(-1, 3)[:, :2].astype(np.float64) / MESH_SIDE
        height, width = rgb.shape[:2]
        points[:, 0] *= width
        points[:, 1] *= height
        return points

    def detect_faces(self, rgb: np.ndarray) -> list[FaceBox]:
        tensor, scale = yunet_input(rgb)
        name = self.detector_session.get_inputs()[0].name
        names = [output.name for output in self.detector_session.get_outputs()]
        values = self.detector_session.run(names, {name: tensor})
        return yunet_decode(dict(zip(names, values)), scale)

    def landmarks(self, rgb: np.ndarray) -> Optional[np.ndarray]:
        faces = self.detect_faces(rgb)
        if not faces:
            return None
        face = max(faces, key=lambda item: item.area)
        left, top, side = face_crop_window(face)
        refined = self.mesh_points(square_crop(rgb, left, top, side))
        if refined is None:
            return None
        refined[:, 0] += left
        refined[:, 1] += top
        return refined

    def embed_aligned(self, aligned_rgb: np.ndarray) -> np.ndarray:
        name = self.embedding_session.get_inputs()[0].name
        vector = self.embedding_session.run(None, {name: embedding_input(aligned_rgb)})[0][0]
        return vector / max(float(np.linalg.norm(vector)), 1e-12)

    def embed_image(self, rgb: np.ndarray) -> Optional[np.ndarray]:
        points = self.landmarks(rgb)
        if points is None:
            return None
        aligned = align_face(rgb, points)
        return None if aligned is None else self.embed_aligned(aligned)
