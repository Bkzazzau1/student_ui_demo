"""Sets the face match threshold from a volunteer study.

The app's 1:1 threshold must come from real people on the real devices, not
from guesses or a public benchmark. This tool scores a study folder with the
same pipeline and the same matching rule the app uses, and reports how often
the real student would be rejected (FRR) and how often another person would
be accepted (FAR) at each threshold.

Study folder (see docs/identity/volunteer_calibration_protocol.md):

    <study>/<volunteer>/registration/*.jpg   the guided registration photos
    <study>/<volunteer>/probes/<device>/*.jpg exam-camera photos per device

usage:
    python -m ai_runtime.face_identity_calibration --study <dir> --out report.json
        [--repo .] [--target-far 0.001] [--max-side 640]

Photos are read in place and never copied. The report holds scores and
counts only, no images and no embeddings.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Iterable, Mapping, Sequence

MIN_REFERENCES = 5
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}


def match_score(probe: Sequence[float], references: Sequence[Sequence[float]]) -> float:
    """The app's decision score: mean of the two best reference cosines
    (``match_official_face_template_1_to_1`` in Rust). Inputs are unit
    vectors."""
    scores = sorted((sum(p * r for p, r in zip(probe, ref)) for ref in references), reverse=True)
    if len(scores) < 2:
        return scores[0] if scores else -1.0
    return (scores[0] + scores[1]) / 2


def collect_scores(
    volunteers: Mapping[str, Mapping[str, object]],
) -> dict[str, list[tuple[str, str, float, bool]]]:
    """Per device: (volunteer, template owner, score, genuine) for every probe
    against every enrolled volunteer's references."""
    enrolled = {
        vid: data["references"]
        for vid, data in volunteers.items()
        if len(data.get("references", [])) >= MIN_REFERENCES
    }
    per_device: dict[str, list[tuple[str, str, float, bool]]] = {}
    for vid, data in volunteers.items():
        if vid not in enrolled:
            continue
        for device, probes in data.get("probes", {}).items():
            rows = per_device.setdefault(device, [])
            for probe in probes:
                for owner, references in enrolled.items():
                    rows.append((vid, owner, match_score(probe, references), owner == vid))
    return per_device


def rates(rows: Iterable[tuple[str, str, float, bool]], threshold: float) -> dict[str, float]:
    genuine = [score for _, _, score, same in rows if same]
    impostor = [score for _, _, score, same in rows if not same]
    false_rejects = sum(score < threshold for score in genuine)
    false_accepts = sum(score >= threshold for score in impostor)
    return {
        "threshold": round(threshold, 4),
        "genuine_comparisons": len(genuine),
        "impostor_comparisons": len(impostor),
        "frr": false_rejects / len(genuine) if genuine else math.nan,
        "far": false_accepts / len(impostor) if impostor else math.nan,
        # 95% upper bound on FAR; with zero false accepts this is ~3/N.
        "far_upper_95": _upper_bound(false_accepts, len(impostor)),
    }


def _upper_bound(events: int, trials: int) -> float:
    if trials == 0:
        return math.nan
    if events == 0:
        return 1 - 0.05 ** (1 / trials)
    # Wilson score interval, one-sided 95%.
    z = 1.645
    p = events / trials
    centre = p + z * z / (2 * trials)
    spread = z * math.sqrt(p * (1 - p) / trials + z * z / (4 * trials * trials))
    return min(1.0, (centre + spread) / (1 + z * z / trials))


def recommend_threshold(
    rows: Sequence[tuple[str, str, float, bool]],
    target_far: float,
) -> dict[str, float]:
    """Lowest threshold (0.01 grid) whose 95% FAR upper bound meets the
    target, so the claim holds with confidence, not just on this sample."""
    for step in range(20, 91):
        threshold = step / 100
        result = rates(rows, threshold)
        if result["far_upper_95"] <= target_far:
            return {**result, "meets_target": True}
    # Not enough impostor comparisons (or too much overlap) to support the
    # target: report the strictest threshold and say so.
    return {**rates(rows, 0.90), "meets_target": False}


def consensus_sessions(
    rows: Sequence[tuple[str, str, float, bool]],
    threshold: float,
    group: int = 3,
) -> dict[str, float]:
    """Simulates the pre-exam rule: groups of ``group`` probes, a pass needs
    at least two matches and more matches than non-matches."""
    by_pair: dict[tuple[str, str], list[float]] = {}
    for vid, owner, score, _ in rows:
        by_pair.setdefault((vid, owner), []).append(score)
    genuine_pass = genuine_total = impostor_pass = impostor_total = 0
    for (vid, owner), scores in by_pair.items():
        for start in range(0, len(scores) - group + 1, group):
            chunk = scores[start : start + group]
            matched = sum(score >= threshold for score in chunk)
            passed = matched >= 2 and matched > len(chunk) - matched
            if vid == owner:
                genuine_total += 1
                genuine_pass += passed
            else:
                impostor_total += 1
                impostor_pass += passed
    return {
        "sessions_genuine": genuine_total,
        "sessions_impostor": impostor_total,
        "session_frr": 1 - genuine_pass / genuine_total if genuine_total else math.nan,
        "session_far": impostor_pass / impostor_total if impostor_total else math.nan,
        "session_far_upper_95": _upper_bound(impostor_pass, impostor_total),
    }


def calibrate(volunteers: Mapping[str, Mapping[str, object]], target_far: float) -> dict[str, object]:
    per_device = collect_scores(volunteers)
    all_rows = [row for rows in per_device.values() for row in rows]
    excluded = sorted(
        vid for vid, data in volunteers.items() if len(data.get("references", [])) < MIN_REFERENCES
    )
    report: dict[str, object] = {
        "volunteers": len(volunteers),
        "enrolled": len(volunteers) - len(excluded),
        "excluded_too_few_references": excluded,
        "target_far": target_far,
        "probe_failures": {vid: data.get("probe_failures", 0) for vid, data in volunteers.items()},
    }
    if not all_rows:
        report["error"] = "no comparisons: need volunteers with references and probes"
        return report
    overall = recommend_threshold(all_rows, target_far)
    report["recommended"] = {
        **overall,
        **consensus_sessions(all_rows, overall["threshold"]),
    }
    report["per_device"] = {
        device: {
            **rates(rows, overall["threshold"]),
            **consensus_sessions(rows, overall["threshold"]),
        }
        for device, rows in sorted(per_device.items())
    }
    report["curve"] = [rates(all_rows, step / 100) for step in range(20, 91, 2)]
    return report


# ---------------------------------------------------------------- images


def _images(folder: Path) -> list[Path]:
    if not folder.is_dir():
        return []
    return sorted(path for path in folder.iterdir() if path.suffix.lower() in IMAGE_SUFFIXES)


def _load_rgb(path: Path, max_side: int):
    import numpy as np
    from PIL import Image

    with Image.open(path) as image:
        image = image.convert("RGB")
        if max(image.size) > max_side:
            scale = max_side / max(image.size)
            image = image.resize(
                (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                Image.BILINEAR,
            )
        return np.asarray(image, dtype=np.uint8)


def embed_study(study: Path, repo: Path, max_side: int) -> dict[str, dict[str, object]]:
    from .face_identity_reference import FaceIdentityReference

    pipeline = FaceIdentityReference.from_repo(repo)
    volunteers: dict[str, dict[str, object]] = {}
    for folder in sorted(path for path in study.iterdir() if path.is_dir()):
        references = []
        for path in _images(folder / "registration"):
            vector = pipeline.embed_image(_load_rgb(path, max_side))
            if vector is not None:
                references.append(vector.tolist())
        probes: dict[str, list[list[float]]] = {}
        failures = 0
        for device in sorted(path for path in (folder / "probes").glob("*") if path.is_dir()):
            for path in _images(device):
                vector = pipeline.embed_image(_load_rgb(path, max_side))
                if vector is None:
                    failures += 1
                    continue
                probes.setdefault(device.name, []).append(vector.tolist())
        volunteers[folder.name] = {
            "references": references,
            "probes": probes,
            "probe_failures": failures,
        }
    return volunteers


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--study", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--repo", type=Path, default=Path("."))
    parser.add_argument("--target-far", type=float, default=0.001)
    parser.add_argument("--max-side", type=int, default=640)
    args = parser.parse_args(argv)
    volunteers = embed_study(args.study, args.repo, args.max_side)
    report = calibrate(volunteers, args.target_far)
    args.out.write_text(json.dumps(report, indent=2))
    recommended = report.get("recommended")
    if recommended:
        if not recommended["meets_target"]:
            print("The study cannot support the target FAR; add volunteers or probes.")
        print(
            f"threshold {recommended['threshold']:.2f}: "
            f"FRR {recommended['frr']:.3%}, FAR {recommended['far']:.4%} "
            f"(95% upper {recommended['far_upper_95']:.4%}); "
            f"3-sample session FRR {recommended['session_frr']:.3%}"
        )
    else:
        print(report.get("error"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
