"""Adapt COCO 2017 human annotations into the frozen E1 base-detector pipeline.

Development-time tooling only. Nothing here runs during a live exam and no
external/hosted AI is contacted.

COCO 2017 already carries crowd-sourced *human* bounding-box annotations for
all eight E1 base classes. This module maps those annotations onto the frozen
E1 taxonomy through one fixed, exact category table (no guessed aliases) and
emits files that feed the existing E1 tools unchanged:

    COCO instances JSON + explicit selection config
        -> ``inventory``  (collection inventory, label-blind source groups)
        -> e1_collection_split  (source-group-safe split plan)
        -> ``stage``      (ingest-compatible staging per assigned split)
        -> e1_annotation_ingest -> e1_dataset_tool -> e1_training_export

Evidence tier: ``open_dataset_human``. These are human annotations supplied by
the open dataset. They are NOT K-SLAS-verified gold labels and NOT teacher
consensus. See ``docs/edge_ai/e1_coco_base_source.md``.

Fail-closed image rules (an image is excluded, never partially labelled):

- its COCO license id is not explicitly allowed by the selection config;
- any E1-target annotation is a crowd region (``iscrowd = 1``);
- any E1-target box is degenerate (< 1 px wide/high after clipping);
- any E1-target box leaves the image by more than ``_EDGE_TOLERANCE_PX``.

Background (no E1 target) images are only taken from images that carry at
least one other COCO annotation, so "no target" is backed by an annotated
image rather than an unannotated one.
"""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import suppress
import hashlib
import json
from pathlib import Path
import sys
from typing import Any, Mapping, Sequence, TextIO

from .e1_annotation_ingest import E1_ANNOTATION_INGEST_SCHEMA_VERSION
from .e1_collection_split import (
    E1_COLLECTION_SCHEMA_VERSION,
    E1_SPLIT_PLAN_SCHEMA_VERSION,
    split_plan_is_group_disjoint,
)
from .e1_training_readiness import BASE_TRAINABLE_CLASSES


E1_COCO_SELECTION_SCHEMA_VERSION = "1.0"
E1_COCO_AUDIT_SCHEMA_VERSION = "1.0"
LABEL_QUALITY = "open_dataset_human"
SOURCE_ID = "coco2017"
SOURCE_NAME = "COCO 2017 (Common Objects in Context)"
ANNOTATION_LICENSE = "CC BY 4.0 (COCO Consortium annotations terms of use)"
_COCO_SPLITS = frozenset({"train2017", "val2017"})
_EDGE_TOLERANCE_PX = 1.0
_MIN_SIDE_PX = 1.0

# Exact COCO category name -> canonical E1 base class. This table is frozen and
# reviewed; it is not an alias guesser. COCO "tv" covers televisions and
# computer monitors, which the E1 taxonomy resolves to canonical `television`.
COCO_TO_E1_BASE: Mapping[str, str] = {
    "person": "person",
    "cell phone": "phone",
    "laptop": "laptop",
    "tv": "television",
    "keyboard": "keyboard",
    "mouse": "mouse",
    "remote": "remote",
    "book": "book",
}

if frozenset(COCO_TO_E1_BASE.values()) != BASE_TRAINABLE_CLASSES:  # pragma: no cover
    raise RuntimeError("COCO_TO_E1_BASE no longer covers the frozen E1 base classes.")


class E1CocoSourceError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _non_negative_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise E1CocoSourceError("invalid_selection", f"{field} must be an explicit non-negative integer.")
    return value


def _rank(seed: str, image_id: int) -> str:
    return hashlib.sha256(f"{seed}\x1f{image_id}".encode("utf-8")).hexdigest()


def _load_json_object(path: Path, code: str) -> Mapping[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError as error:
        raise E1CocoSourceError(code, f"File not found: {path}") from error
    except json.JSONDecodeError as error:
        raise E1CocoSourceError(code, f"Malformed JSON in {path}: {error.msg}") from error
    if not isinstance(data, Mapping):
        raise E1CocoSourceError(code, f"Top-level JSON in {path} must be an object.")
    return data


def _group_id(coco_split: str, image_id: int) -> str:
    return f"{SOURCE_ID}:{coco_split}:{image_id}"


def _parse_group_id(value: str) -> tuple[str, int]:
    parts = value.split(":")
    if len(parts) != 3 or parts[0] != SOURCE_ID or parts[1] not in _COCO_SPLITS or not parts[2].isdigit():
        raise E1CocoSourceError("foreign_source_group", f"Not a COCO source group created by this tool: {value!r}")
    return parts[1], int(parts[2])


class CocoIndex:
    """Validated view over one COCO ``instances_*.json`` file."""

    def __init__(self, instances: Mapping[str, Any]):
        categories = instances.get("categories")
        images = instances.get("images")
        annotations = instances.get("annotations")
        licenses = instances.get("licenses")
        if not all(isinstance(v, list) for v in (categories, images, annotations, licenses)):
            raise E1CocoSourceError("invalid_instances", "COCO instances JSON needs categories/images/annotations/licenses lists.")
        names = {c.get("id"): _text(c.get("name")) for c in categories if isinstance(c, Mapping)}
        self.target_category_ids: dict[int, str] = {}
        for coco_name, e1_class in COCO_TO_E1_BASE.items():
            ids = [cid for cid, name in names.items() if name == coco_name]
            if len(ids) != 1:
                raise E1CocoSourceError("category_mapping_mismatch", f"COCO category {coco_name!r} must appear exactly once.")
            self.target_category_ids[ids[0]] = e1_class
        self.licenses = {
            lic["id"]: {"id": lic["id"], "name": _text(lic.get("name")), "url": _text(lic.get("url"))}
            for lic in licenses
            if isinstance(lic, Mapping) and isinstance(lic.get("id"), int)
        }
        self.images: dict[int, Mapping[str, Any]] = {}
        for image in images:
            if not isinstance(image, Mapping) or not isinstance(image.get("id"), int):
                raise E1CocoSourceError("invalid_instances", "Every COCO image needs an integer id.")
            self.images[image["id"]] = image
        self.annotations: dict[int, list[Mapping[str, Any]]] = {}
        for annotation in annotations:
            if not isinstance(annotation, Mapping):
                raise E1CocoSourceError("invalid_instances", "Every COCO annotation must be an object.")
            self.annotations.setdefault(annotation.get("image_id"), []).append(annotation)

    def classify(self, image_id: int, allowed_license_ids: frozenset[int]) -> tuple[str, list[dict[str, Any]]]:
        """Return (tier_or_exclusion_reason, clipped E1 annotations)."""

        image = self.images[image_id]
        width, height = image.get("width"), image.get("height")
        if not (isinstance(width, int) and isinstance(height, int) and width > 0 and height > 0):
            return "excluded_invalid_dimensions", []
        if image.get("license") not in allowed_license_ids:
            return "excluded_license_not_allowed", []
        all_annotations = self.annotations.get(image_id, [])
        boxes: list[dict[str, Any]] = []
        seen: set[tuple[Any, ...]] = set()
        for annotation in all_annotations:
            e1_class = self.target_category_ids.get(annotation.get("category_id"))
            if e1_class is None:
                continue
            if annotation.get("iscrowd"):
                return "excluded_crowd_target", []
            bbox = annotation.get("bbox")
            if not (isinstance(bbox, list) and len(bbox) == 4 and all(isinstance(v, (int, float)) for v in bbox)):
                return "excluded_invalid_target_box", []
            x, y, w, h = (float(v) for v in bbox)
            x1, y1, x2, y2 = x, y, x + w, y + h
            if x1 < -_EDGE_TOLERANCE_PX or y1 < -_EDGE_TOLERANCE_PX or x2 > width + _EDGE_TOLERANCE_PX or y2 > height + _EDGE_TOLERANCE_PX:
                return "excluded_target_box_outside_image", []
            x1, y1 = max(0.0, x1), max(0.0, y1)
            x2, y2 = min(float(width), x2), min(float(height), y2)
            cw, ch = x2 - x1, y2 - y1
            if cw < _MIN_SIDE_PX or ch < _MIN_SIDE_PX:
                return "excluded_degenerate_target_box", []
            # Same identity rule as e1_annotation_ingest (class + normalized box at 1e-10).
            key = (e1_class, round(x1 / width, 10), round(y1 / height, 10), round(cw / width, 10), round(ch / height, 10))
            if key in seen:
                continue
            seen.add(key)
            boxes.append({
                "canonical_object_id": e1_class,
                "bbox_xywh_pixels": [x1, y1, cw, ch],
                "coco_annotation_id": annotation.get("id"),
                "clipped": (x1, y1, cw, ch) != (x, y, w, h),
            })
        if not boxes:
            return ("background" if all_annotations else "excluded_unannotated_image"), []
        if any(b["canonical_object_id"] != "person" for b in boxes):
            return "non_person_target", boxes
        return "person_only", boxes


def _read_selection(selection: Mapping[str, Any]) -> dict[str, Any]:
    if _text(selection.get("selection_schema_version")) != E1_COCO_SELECTION_SCHEMA_VERSION:
        raise E1CocoSourceError("invalid_selection", f"selection_schema_version must be {E1_COCO_SELECTION_SCHEMA_VERSION!r}.")
    fields = {k: _text(selection.get(k)) for k in ("dataset_id", "dataset_version", "coco_split", "image_dir", "selection_seed", "split_seed")}
    missing = [k for k, v in fields.items() if not v]
    if missing:
        raise E1CocoSourceError("invalid_selection", f"Selection must explicitly supply: {', '.join(missing)}.")
    if fields["coco_split"] not in _COCO_SPLITS:
        raise E1CocoSourceError("invalid_selection", "coco_split must be train2017 or val2017.")
    licenses = selection.get("allowed_license_ids")
    if not isinstance(licenses, list) or not licenses or not all(isinstance(v, int) and not isinstance(v, bool) for v in licenses):
        raise E1CocoSourceError("invalid_selection", "allowed_license_ids must be an explicit non-empty list of COCO license ids.")
    weights = selection.get("split_weights")
    if not isinstance(weights, Mapping):
        raise E1CocoSourceError("invalid_selection", "split_weights must be supplied explicitly.")
    return {
        **fields,
        "image_dir": fields["image_dir"].replace("\\", "/").strip("/"),
        "allowed_license_ids": frozenset(licenses),
        "person_only_limit": _non_negative_int(selection.get("person_only_limit"), "person_only_limit"),
        "background_limit": _non_negative_int(selection.get("background_limit"), "background_limit"),
        "split_weights": dict(weights),
    }


def build_inventory(instances: Mapping[str, Any], selection: Mapping[str, Any]) -> dict[str, Any]:
    config = _read_selection(selection)
    index = CocoIndex(instances)
    tiers: dict[str, list[int]] = {"non_person_target": [], "person_only": [], "background": []}
    reasons: Counter[str] = Counter()
    for image_id in sorted(index.images):
        tier, _ = index.classify(image_id, config["allowed_license_ids"])
        reasons[tier] += 1
        if tier in tiers:
            tiers[tier].append(image_id)
    seed = config["selection_seed"]
    chosen = list(tiers["non_person_target"])
    for tier, limit in (("person_only", config["person_only_limit"]), ("background", config["background_limit"])):
        chosen.extend(sorted(tiers[tier], key=lambda i: (_rank(seed, i), i))[:limit])
    records = []
    for image_id in sorted(chosen):
        image = index.images[image_id]
        file_name = _text(image.get("file_name"))
        if not file_name or "/" in file_name or "\\" in file_name:
            raise E1CocoSourceError("invalid_instances", f"Unsafe COCO file_name for image {image_id}.")
        records.append({
            "source_group_id": _group_id(config["coco_split"], image_id),
            "image_path": f"{config['image_dir']}/{file_name}",
            "width": image["width"],
            "height": image["height"],
        })
    if not records:
        raise E1CocoSourceError("empty_selection", "The selection produced no images.")
    return {
        "collection_schema_version": E1_COLLECTION_SCHEMA_VERSION,
        "dataset_id": config["dataset_id"],
        "dataset_version": config["dataset_version"],
        "model_role": "base",
        "split_seed": config["split_seed"],
        "split_weights": config["split_weights"],
        "coco_selection": {
            "selection_schema_version": E1_COCO_SELECTION_SCHEMA_VERSION,
            "source_id": SOURCE_ID,
            "coco_split": config["coco_split"],
            "selection_seed": seed,
            "allowed_license_ids": sorted(config["allowed_license_ids"]),
            "person_only_limit": config["person_only_limit"],
            "background_limit": config["background_limit"],
            "available": {k: len(v) for k, v in tiers.items()},
            "selected": {
                "non_person_target": len(tiers["non_person_target"]),
                "person_only": min(config["person_only_limit"], len(tiers["person_only"])),
                "background": min(config["background_limit"], len(tiers["background"])),
            },
            "image_outcomes": dict(sorted(reasons.items())),
            "label_blind_note": "Selection uses COCO labels; split assignment (e1_collection_split) remains label-blind.",
        },
        "records": records,
    }


def build_staging(instances: Mapping[str, Any], plan: Mapping[str, Any], split: str, allowed_license_ids: Sequence[int]) -> dict[str, Any]:
    if _text(plan.get("split_plan_schema_version")) != E1_SPLIT_PLAN_SCHEMA_VERSION:
        raise E1CocoSourceError("invalid_plan", "Input is not an E1 split plan.")
    if _text(plan.get("model_role")) != "base":
        raise E1CocoSourceError("invalid_plan", "COCO source supports the base role only.")
    if not split_plan_is_group_disjoint(plan):
        raise E1CocoSourceError("invalid_plan", "Split plan leaks a source group across splits.")
    if split not in {"train", "validation", "test"}:
        raise E1CocoSourceError("invalid_split", "split must be train, validation, or test.")
    allowed = frozenset(allowed_license_ids)
    index = CocoIndex(instances)
    records, class_counts, clipped, provenance_licenses = [], Counter(), 0, Counter()
    for planned in plan.get("records", []):
        if planned.get("split") != split:
            continue
        coco_split, image_id = _parse_group_id(_text(planned.get("source_group_id")))
        image = index.images.get(image_id)
        if image is None:
            raise E1CocoSourceError("image_not_in_instances", f"Image {image_id} is not in the supplied {coco_split} instances.")
        if (planned.get("width"), planned.get("height")) != (image.get("width"), image.get("height")) or not _text(planned.get("image_path")).endswith("/" + _text(image.get("file_name"))):
            raise E1CocoSourceError("plan_instances_mismatch", f"Plan record for image {image_id} does not match the instances file.")
        tier, boxes = index.classify(image_id, allowed)
        if tier.startswith("excluded"):
            raise E1CocoSourceError("plan_contains_excluded_image", f"Image {image_id} is now {tier}; rebuild the inventory.")
        clipped += sum(1 for b in boxes if b["clipped"])
        class_counts.update(b["canonical_object_id"] for b in boxes)
        license_entry = index.licenses.get(image.get("license"), {"id": image.get("license"), "name": "", "url": ""})
        provenance_licenses[license_entry["name"] or str(license_entry["id"])] += 1
        records.append({
            "source_group_id": planned["source_group_id"],
            "image_path": planned["image_path"],
            "width": planned["width"],
            "height": planned["height"],
            "annotations": [{"canonical_object_id": b["canonical_object_id"], "bbox_xywh_pixels": b["bbox_xywh_pixels"]} for b in boxes],
            "provenance": {
                "kind": "open_source_dataset",
                "source_id": SOURCE_ID,
                "source_name": SOURCE_NAME,
                "source_item_id": f"{coco_split}/{image_id}",
                "license": license_entry,
                "source_ref": _text(image.get("coco_url")),
                "flickr_url": _text(image.get("flickr_url")),
                "coco_annotation_ids": [b["coco_annotation_id"] for b in boxes],
                "selection_tier": tier,
            },
        })
    if not records:
        raise E1CocoSourceError("empty_split", f"The split plan assigns no records to {split}.")
    return {
        "ingest_schema_version": E1_ANNOTATION_INGEST_SCHEMA_VERSION,
        "dataset_id": plan["dataset_id"],
        "dataset_version": plan["dataset_version"],
        "model_role": "base",
        "split": split,
        "open_dataset_audit": {
            "audit_schema_version": E1_COCO_AUDIT_SCHEMA_VERSION,
            "label_quality": LABEL_QUALITY,
            "annotation_origin": "COCO 2017 crowd-sourced human annotation",
            "human_verified_by_kslas": False,
            "is_teacher_consensus": False,
            "is_gold": False,
            "annotation_license": ANNOTATION_LICENSE,
            "image_license_counts": dict(sorted(provenance_licenses.items())),
            "category_mapping": dict(COCO_TO_E1_BASE),
            "fail_closed_rules": [
                "crowd target region excludes the image",
                f"target box outside image by more than {_EDGE_TOLERANCE_PX} px excludes the image",
                f"target box under {_MIN_SIDE_PX} px after clipping excludes the image",
                "image license must be explicitly allowed",
                "background images must carry other COCO annotations",
            ],
            "boxes_clipped_to_image": clipped,
            "annotation_counts": dict(sorted(class_counts.items())),
            "record_count": len(records),
            "live_external_ai": "forbidden",
            "retain_note": "Keep this staging file next to the canonical manifest; ingest does not copy provenance.",
        },
        "records": records,
    }


def _write_new(path: Path, payload: Mapping[str, Any], force: bool) -> None:
    if path.exists() and not force:
        raise E1CocoSourceError("output_exists", f"Output already exists; pass --force to replace it: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as handle:
            json.dump(payload, handle, indent=2, sort_keys=False)
            handle.write("\n")
        temporary.replace(path)
    finally:
        with suppress(FileNotFoundError):
            temporary.unlink()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m ai_runtime.e1_coco_source", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    inventory = sub.add_parser("inventory", help="Select COCO images and write an E1 collection inventory.")
    inventory.add_argument("--instances", type=Path, required=True)
    inventory.add_argument("--selection", type=Path, required=True)
    inventory.add_argument("--output", type=Path, required=True)
    stage = sub.add_parser("stage", help="Write ingest-compatible staging for one split of a split plan.")
    stage.add_argument("--instances", type=Path, required=True)
    stage.add_argument("--plan", type=Path, required=True)
    stage.add_argument("--selection", type=Path, required=True, help="Selection used for the inventory (license allow-list).")
    stage.add_argument("--split", required=True)
    stage.add_argument("--output", type=Path, required=True)
    for command in (inventory, stage):
        command.add_argument("--force", action="store_true", help="Replace an existing output file.")
        command.add_argument("--pretty", action="store_true", help="Pretty-print the command result JSON.")
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO | None = None) -> int:
    out = stdout or sys.stdout
    args = _build_parser().parse_args(argv)
    try:
        instances = _load_json_object(args.instances, "invalid_instances")
        selection = _load_json_object(args.selection, "invalid_selection")
        if args.command == "inventory":
            payload = build_inventory(instances, selection)
            summary = {"ok": True, "command": "inventory", "output": str(args.output), "record_count": len(payload["records"]), **payload["coco_selection"]}
        else:
            licenses = _read_selection(selection)["allowed_license_ids"]
            plan = _load_json_object(args.plan, "invalid_plan")
            payload = build_staging(instances, plan, _text(args.split).lower(), sorted(licenses))
            summary = {"ok": True, "command": "stage", "output": str(args.output), "split": payload["split"], **{k: payload["open_dataset_audit"][k] for k in ("record_count", "annotation_counts", "boxes_clipped_to_image", "image_license_counts")}}
        _write_new(args.output, payload, args.force)
    except E1CocoSourceError as error:
        json.dump({"ok": False, "error": {"code": error.code, "message": error.message}}, out, indent=2 if args.pretty else None)
        out.write("\n")
        return 1
    json.dump(summary, out, indent=2 if args.pretty else None)
    out.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
