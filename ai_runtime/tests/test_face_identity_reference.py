"""Checks for the face identity reference pipeline (no real faces used)."""

import base64
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "ai_runtime/tests/fixtures/face_alignment_golden.json"
NUMPY = importlib.util.find_spec("numpy") is not None
ORT = NUMPY and importlib.util.find_spec("onnxruntime") is not None


def _real_model(path: Path) -> bool:
    """False for a Git LFS pointer checkout."""
    return path.exists() and path.stat().st_size > 100_000


@unittest.skipUnless(NUMPY, "numpy is not installed")
class AlignmentTests(unittest.TestCase):
    def setUp(self):
        import numpy as np

        from ai_runtime import face_identity_reference as ref

        self.np = np
        self.ref = ref

    def test_similarity_recovers_a_known_transform(self):
        np, ref = self.np, self.ref
        angle, scale, shift = 0.3, 1.7, np.array([12.5, -4.0])
        rotation = np.array([[np.cos(angle), -np.sin(angle)], [np.sin(angle), np.cos(angle)]])
        source = ref.ARCFACE_TEMPLATE
        target = source @ (scale * rotation).T + shift
        matrix = ref.similarity_least_squares(source, target)
        np.testing.assert_allclose(matrix[:, :2], scale * rotation, atol=1e-9)
        np.testing.assert_allclose(matrix[:, 2], shift, atol=1e-9)

    def test_similarity_never_reflects(self):
        np, ref = self.np, self.ref
        mirrored = ref.ARCFACE_TEMPLATE * np.array([-1.0, 1.0])
        matrix = ref.similarity_least_squares(mirrored, ref.ARCFACE_TEMPLATE)
        self.assertGreaterEqual(np.linalg.det(matrix[:, :2]), 0)

    def test_identity_warp_copies_pixels_and_blackens_outside(self):
        np, ref = self.np, self.ref
        image = ref.procedural_rgb(80, 60)
        identity = np.array([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])
        out = ref.warp_bilinear(image, identity, side=112)
        np.testing.assert_array_equal(out[:60, :80], image)
        self.assertEqual(int(out[100, 100].max()), 0)

    def test_alignment_matches_the_shared_golden_fixture(self):
        np, ref = self.np, self.ref
        golden = json.loads(FIXTURE.read_text())
        self.assertEqual(golden["preprocessing_version"], ref.PREPROCESSING_VERSION)
        image = ref.procedural_rgb(golden["image_width"], golden["image_height"])
        matrix = ref.similarity_least_squares(np.array(golden["points"]), ref.ARCFACE_TEMPLATE)
        np.testing.assert_allclose(matrix, np.array(golden["matrix"]), atol=1e-12)
        aligned = ref.warp_bilinear(image, matrix)
        self.assertEqual(hashlib.sha256(aligned.tobytes()).hexdigest(), golden["aligned_rgb_sha256"])
        self.assertEqual(base64.b64decode(golden["aligned_rgb_b64"]), aligned.tobytes())

    def test_five_points_use_eye_corner_midpoints(self):
        np, ref = self.np, self.ref
        points = np.zeros((478, 2))
        points[33], points[133] = (10, 20), (20, 20)
        points[362], points[263] = (40, 22), (50, 22)
        points[1], points[61], points[291] = (30, 35), (18, 50), (42, 50)
        five = ref.five_points(points)
        np.testing.assert_allclose(five, [[15, 20], [45, 22], [30, 35], [18, 50], [42, 50]])

    def test_embedding_input_is_raw_rgb_nchw(self):
        np, ref = self.np, self.ref
        aligned = np.zeros((112, 112, 3), dtype=np.uint8)
        aligned[..., 0], aligned[..., 1], aligned[..., 2] = 10, 128, 250
        tensor = ref.embedding_input(aligned)
        self.assertEqual(tensor.shape, (1, 3, 112, 112))
        self.assertEqual(
            [float(tensor[0, c, 5, 5]) for c in range(3)],
            [10.0, 128.0, 250.0],
        )


@unittest.skipUnless(NUMPY, "numpy is not installed")
class DetectorDecodeTests(unittest.TestCase):
    def setUp(self):
        import numpy as np

        from ai_runtime import face_identity_reference as ref

        self.np = np
        self.ref = ref

    def outputs(self):
        np = self.np
        out = {}
        for stride in (8, 16, 32):
            anchors = (640 // stride) ** 2
            out[f"cls_{stride}"] = np.zeros((1, anchors, 1), np.float32)
            out[f"obj_{stride}"] = np.zeros((1, anchors, 1), np.float32)
            out[f"bbox_{stride}"] = np.zeros((1, anchors, 4), np.float32)
            out[f"kps_{stride}"] = np.zeros((1, anchors, 10), np.float32)
        return out

    def test_decodes_one_face_with_keypoints_in_source_pixels(self):
        np, ref = self.np, self.ref
        out = self.outputs()
        cols = 640 // 16
        index = 10 * cols + 20  # row 10, col 20 on the stride-16 grid
        out["cls_16"][0, index, 0] = 0.9
        out["obj_16"][0, index, 0] = 0.9
        out["bbox_16"][0, index] = [0.5, 0.25, np.log(4.0), np.log(5.0)]
        out["kps_16"][0, index] = [0.1, 0.2, 0.9, 0.2, 0.5, 0.5, 0.2, 0.8, 0.8, 0.8]
        faces = ref.yunet_decode(out, scale=0.5)
        self.assertEqual(len(faces), 1)
        face = faces[0]
        self.assertAlmostEqual(face.score, 0.9, places=6)
        # centre (20.5, 10.25)*16 = (328, 164); size (64, 80); then / 0.5
        self.assertAlmostEqual(face.x, (328 - 32) / 0.5, places=4)
        self.assertAlmostEqual(face.y, (164 - 40) / 0.5, places=4)
        self.assertAlmostEqual(face.width, 128, places=4)
        self.assertAlmostEqual(face.height, 160, places=4)
        self.assertAlmostEqual(face.keypoints[0, 0], (0.1 + 20) * 16 / 0.5, places=4)
        self.assertAlmostEqual(face.keypoints[4, 1], (0.8 + 10) * 16 / 0.5, places=4)

    def test_low_scores_are_dropped_and_overlaps_suppressed(self):
        out = self.outputs()
        cols = 640 // 8
        for index, score in ((100, 0.95), (101, 0.9), (5000, 0.5)):
            out["cls_8"][0, index, 0] = score
            out["obj_8"][0, index, 0] = score
            out["bbox_8"][0, index] = [0.0, 0.0, 2.0, 2.0]
        faces = self.ref.yunet_decode(out, scale=1.0)
        self.assertEqual(len(faces), 1)
        self.assertAlmostEqual(faces[0].score, 0.95, places=6)
        self.assertEqual(cols, 80)

    def test_detector_input_is_bgr_padded_and_never_enlarged(self):
        np, ref = self.np, self.ref
        image = np.zeros((240, 320, 3), np.uint8)
        image[..., 0] = 200  # red
        tensor, scale = ref.yunet_input(image)
        self.assertEqual(scale, 1.0)
        self.assertEqual(tensor.shape, (1, 3, 640, 640))
        self.assertEqual(float(tensor[0, 2, 10, 10]), 200.0)  # red is the last BGR plane
        self.assertEqual(float(tensor[0, 2, 300, 10]), 0.0)  # padding
        _, big_scale = ref.yunet_input(np.zeros((960, 1280, 3), np.uint8))
        self.assertAlmostEqual(big_scale, 0.5)

    def test_face_crop_is_square_and_centred(self):
        np, ref = self.np, self.ref
        face = ref.FaceBox(x=100, y=50, width=80, height=100, score=0.9, keypoints=np.zeros((5, 2)))
        left, top, side = ref.face_crop_window(face)
        self.assertEqual(side, 150)
        self.assertEqual((left, top), (65, 25))


SFACE = ROOT / "assets/models/face_embedding_sface/face_recognition_sface_2021dec.onnx"


@unittest.skipUnless(ORT and _real_model(SFACE), "onnxruntime or the SFace model is unavailable")
class SFaceInputContractTests(unittest.TestCase):
    def test_model_normalizes_inside_the_graph(self):
        """The model subtracts 127.5 and multiplies by 1/128 itself, so the
        app must feed raw 0..255 values (normalizing twice breaks matching)."""
        import numpy as np
        import onnxruntime as ort

        options = ort.SessionOptions()
        options.log_severity_level = 3
        session = ort.InferenceSession(str(SFACE), options, providers=["CPUExecutionProvider"])
        x = np.random.default_rng(0).uniform(0, 255, (1, 3, 112, 112)).astype(np.float32)
        base = session.run(None, {"data": x})[0]
        for name, value in (("scalar_op1", 127.5), ("scalar_op2", 0.0078125)):
            forced = session.run(None, {"data": x, name: np.array([value], np.float32)})[0]
            np.testing.assert_allclose(forced, base, atol=1e-5)


if __name__ == "__main__":
    unittest.main()
