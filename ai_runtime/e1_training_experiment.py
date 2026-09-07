"""Build an auditable E1 YOLO training experiment plan.

Development-time tooling only. This module does not train a model, download a
checkpoint, or participate in live exam inference. It validates an explicit
experiment specification against a previously validated E1 YOLO export and
writes a deterministic plan that a later training runner can execute.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any, Mapping, Sequence, TextIO

from .e1_training_export import (
    E1_TRAINING_EXPORT_SCHEMA_VERSION,
    class_order_for_role,
)
from .e1_training_readiness import E1_TAXONOMY_VERSION


E1_TRAINING_EXPERIMENT_SCHEMA_VERSION = "1.0"
E1_TRAINING_PLAN_SCHEMA_VERSION = "1.0"

_REQUIRED_TRAINER_ARGS = frozenset(
    {
        "epochs",
        "imgsz",
        "batch",
        "workers",
        "device",
        "optimizer",
        "lr0",
        "weight_decay",
        "patience",
        "deterministic",
    }
)
_RESERVED_TRAINER_ARGS = frozenset(
    {
        "model",
        "data",
        "project",
        "name",
        "exist_ok",
        "seed",
        "task",
        "mode",
    }
)
_SAFE_ID_CHARS = frozenset(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
)


class E1TrainingExperimentInputError(ValueError):
    """Raised when an experiment cannot be planned safely."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _read_json_object(path: Path, *, code_prefix: str) -> Mapping[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise E1TrainingExperimentInputError(
            f"{code_prefix}_read_error", f"Could not read {path}: {exc}"
        ) from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise E1TrainingExperimentInputError(
            f"invalid_{code_prefix}_json",
            f"Invalid JSON in {path} at line {exc.lineno}, column {exc.colno}: {exc.msg}",
        ) from exc
    if not isinstance(value, Mapping):
        raise E1TrainingExperimentInputError(
            f"{code_prefix}_root_not_object",
            f"Top-level JSON in {path} must be an object.",
        )
    return value


def _read_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _safe_identifier(value: str) -> bool:
    return (
        bool(value)
        and len(value) <= 128
        and value not in {".", ".."}
        and all(character in _SAFE_ID_CHARS for character in value)
    )


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _resolve_from_spec(spec_path: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path.resolve()
    return (spec_path.parent / path).resolve()


def _finite_number(value: Any) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(float(value))
    )


def _validate_positive_int(value: Any, field: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise E1TrainingExperimentInputError(
            "invalid_trainer_arg", f"{field} must be a positive integer."
        )


def _validate_non_negative_int(value: Any, field: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise E1TrainingExperimentInputError(
            "invalid_trainer_arg", f"{field} must be a non-negative integer."
        )


def _validate_positive_number(value: Any, field: str) -> None:
    if not _finite_number(value) or float(value) <= 0:
        raise E1TrainingExperimentInputError(
            "invalid_trainer_arg", f"{field} must be a positive finite number."
        )


def _validate_non_negative_number(value: Any, field: str) -> None:
    if not _finite_number(value) or float(value) < 0:
        raise E1TrainingExperimentInputError(
            "invalid_trainer_arg",
            f"{field} must be a non-negative finite number.",
        )


def _safe_arg_key(key: Any) -> bool:
    return (
        isinstance(key, str)
        and bool(key)
        and key[0].isalpha()
        and all(character.isalnum() or character == "_" for character in key)
    )


def _safe_arg_value(value: Any) -> bool:
    if isinstance(value, bool):
        return True
    if _finite_number(value):
        return True
    return isinstance(value, str) and bool(value.strip()) and "\x00" not in value


def _normalized_arg_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return format(value, ".15g")
    return str(value)


def _validate_trainer_args(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, Mapping):
        raise E1TrainingExperimentInputError(
            "invalid_trainer_args", "trainer_args must be an object."
        )
    missing = sorted(_REQUIRED_TRAINER_ARGS - set(raw))
    if missing:
        raise E1TrainingExperimentInputError(
            "missing_trainer_args",
            "trainer_args must explicitly define: " + ", ".join(missing),
        )

    normalized: dict[str, Any] = {}
    for key, value in raw.items():
        if not _safe_arg_key(key):
            raise E1TrainingExperimentInputError(
                "unsafe_trainer_arg_key", f"Unsafe trainer argument key: {key!r}."
            )
        if key in _RESERVED_TRAINER_ARGS:
            raise E1TrainingExperimentInputError(
                "reserved_trainer_arg",
                f"trainer_args may not override reserved argument {key!r}.",
            )
        if not _safe_arg_value(value):
            raise E1TrainingExperimentInputError(
                "invalid_trainer_arg_value",
                f"trainer_args.{key} must be a finite scalar or non-empty string.",
            )
        normalized[key] = value

    _validate_positive_int(normalized["epochs"], "trainer_args.epochs")
    _validate_positive_int(normalized["imgsz"], "trainer_args.imgsz")
    _validate_positive_int(normalized["batch"], "trainer_args.batch")
    _validate_non_negative_int(normalized["workers"], "trainer_args.workers")
    if not isinstance(normalized["device"], str) or not normalized["device"].strip():
        raise E1TrainingExperimentInputError(
            "invalid_trainer_arg", "trainer_args.device must be a non-empty string."
        )
    if not isinstance(normalized["optimizer"], str) or not normalized["optimizer"].strip():
        raise E1TrainingExperimentInputError(
            "invalid_trainer_arg",
            "trainer_args.optimizer must be a non-empty string.",
        )
    _validate_positive_number(normalized["lr0"], "trainer_args.lr0")
    _validate_non_negative_number(
        normalized["weight_decay"], "trainer_args.weight_decay"
    )
    _validate_non_negative_int(normalized["patience"], "trainer_args.patience")
    if not isinstance(normalized["deterministic"], bool):
        raise E1TrainingExperimentInputError(
            "invalid_trainer_arg",
            "trainer_args.deterministic must be true or false.",
        )
    return normalized


def _validate_augmentation_policy(raw: Any) -> tuple[str, dict[str, Any]]:
    if not isinstance(raw, Mapping):
        raise E1TrainingExperimentInputError(
            "invalid_augmentation_policy", "augmentation_policy must be an object."
        )
    mode = _read_string(raw.get("mode")).lower()
    if mode not in {"framework_defaults", "explicit"}:
        raise E1TrainingExperimentInputError(
            "invalid_augmentation_mode",
            "augmentation_policy.mode must be framework_defaults or explicit.",
        )
    args = raw.get("args", {})
    if not isinstance(args, Mapping):
        raise E1TrainingExperimentInputError(
            "invalid_augmentation_args", "augmentation_policy.args must be an object."
        )
    if mode == "framework_defaults" and args:
        raise E1TrainingExperimentInputError(
            "unexpected_augmentation_args",
            "framework_defaults mode must not also provide augmentation args.",
        )

    normalized: dict[str, Any] = {}
    for key, value in args.items():
        if not _safe_arg_key(key):
            raise E1TrainingExperimentInputError(
                "unsafe_augmentation_arg_key",
                f"Unsafe augmentation argument key: {key!r}.",
            )
        if key in _RESERVED_TRAINER_ARGS or key in _REQUIRED_TRAINER_ARGS:
            raise E1TrainingExperimentInputError(
                "conflicting_augmentation_arg",
                f"augmentation_policy.args may not override {key!r}.",
            )
        if not _safe_arg_value(value):
            raise E1TrainingExperimentInputError(
                "invalid_augmentation_arg_value",
                f"augmentation_policy.args.{key} must be a finite scalar or non-empty string.",
            )
        normalized[key] = value
    if mode == "explicit" and not normalized:
        raise E1TrainingExperimentInputError(
            "empty_explicit_augmentation",
            "explicit augmentation mode requires at least one explicit argument.",
        )
    return mode, normalized


def _validate_export_manifest(
    export_manifest: Mapping[str, Any], *, expected_role: str
) -> tuple[str, str, list[dict[str, Any]]]:
    if export_manifest.get("export_schema_version") != E1_TRAINING_EXPORT_SCHEMA_VERSION:
        raise E1TrainingExperimentInputError(
            "export_schema_mismatch", "Training export schema version is not supported."
        )
    if export_manifest.get("taxonomy_version") != E1_TAXONOMY_VERSION:
        raise E1TrainingExperimentInputError(
            "taxonomy_mismatch", "Training export does not use the frozen E1 taxonomy."
        )
    role = _read_string(export_manifest.get("model_role")).lower()
    if role != expected_role:
        raise E1TrainingExperimentInputError(
            "model_role_mismatch",
            f"Experiment role {expected_role!r} does not match export role {role!r}.",
        )
    class_order = class_order_for_role(role)
    expected_map = [
        {"index": index, "canonical_object_id": canonical_id}
        for index, canonical_id in enumerate(class_order)
    ]
    class_map = export_manifest.get("class_map")
    if class_map != expected_map:
        raise E1TrainingExperimentInputError(
            "class_map_mismatch",
            "Training export class map does not match the frozen E1 class order.",
        )
    dataset_id = _read_string(export_manifest.get("dataset_id"))
    dataset_version = _read_string(export_manifest.get("dataset_version"))
    if not dataset_id or not dataset_version:
        raise E1TrainingExperimentInputError(
            "missing_dataset_provenance",
            "Training export must contain dataset_id and dataset_version.",
        )
    splits = export_manifest.get("splits")
    if not isinstance(splits, Mapping):
        raise E1TrainingExperimentInputError(
            "invalid_export_splits", "Training export splits must be an object."
        )
    for split in ("train", "validation"):
        summary = splits.get(split)
        if not isinstance(summary, Mapping):
            raise E1TrainingExperimentInputError(
                "missing_training_split", f"Training export is missing {split!r}."
            )
        count = summary.get("sample_count")
        if not isinstance(count, int) or isinstance(count, bool) or count <= 0:
            raise E1TrainingExperimentInputError(
                "empty_training_split",
                f"Training export {split!r} must contain at least one sample.",
            )
    return dataset_id, dataset_version, expected_map


def build_training_plan(
    spec_path: Path,
    export_dir: Path,
) -> dict[str, Any]:
    spec_path = spec_path.resolve()
    export_dir = export_dir.resolve()
    spec = _read_json_object(spec_path, code_prefix="experiment_spec")

    if spec.get("schema_version") != E1_TRAINING_EXPERIMENT_SCHEMA_VERSION:
        raise E1TrainingExperimentInputError(
            "experiment_schema_mismatch", "Unsupported experiment schema_version."
        )
    experiment_id = _read_string(spec.get("experiment_id"))
    if not _safe_identifier(experiment_id):
        raise E1TrainingExperimentInputError(
            "invalid_experiment_id",
            "experiment_id must be a portable identifier using letters, digits, dot, underscore or hyphen.",
        )
    framework = _read_string(spec.get("framework")).lower()
    if framework != "ultralytics":
        raise E1TrainingExperimentInputError(
            "unsupported_framework", "This plan contract currently supports ultralytics only."
        )
    framework_version = _read_string(spec.get("framework_version"))
    if not framework_version:
        raise E1TrainingExperimentInputError(
            "missing_framework_version",
            "framework_version must be pinned explicitly for reproducibility.",
        )
    task = _read_string(spec.get("task")).lower()
    if task != "detect":
        raise E1TrainingExperimentInputError(
            "unsupported_task", "E1 training experiments currently support detect only."
        )
    role = _read_string(spec.get("model_role")).lower()
    if not class_order_for_role(role):
        raise E1TrainingExperimentInputError(
            "invalid_model_role", "model_role must be base or specialist."
        )
    seed = spec.get("seed")
    _validate_non_negative_int(seed, "seed")

    checkpoint_value = _read_string(spec.get("checkpoint_path"))
    project_value = _read_string(spec.get("project_dir"))
    if not checkpoint_value:
        raise E1TrainingExperimentInputError(
            "missing_checkpoint_path", "checkpoint_path is required."
        )
    if not project_value:
        raise E1TrainingExperimentInputError(
            "missing_project_dir", "project_dir is required."
        )
    checkpoint = _resolve_from_spec(spec_path, checkpoint_value)
    if not checkpoint.is_file() or checkpoint.stat().st_size <= 0:
        raise E1TrainingExperimentInputError(
            "checkpoint_unavailable",
            f"Explicit local checkpoint is missing or empty: {checkpoint}",
        )
    project_dir = _resolve_from_spec(spec_path, project_value)
    run_dir = project_dir / experiment_id
    if run_dir.exists():
        raise E1TrainingExperimentInputError(
            "run_output_exists",
            f"Refusing to plan into an existing run directory: {run_dir}",
        )

    trainer_args = _validate_trainer_args(spec.get("trainer_args"))
    augmentation_mode, augmentation_args = _validate_augmentation_policy(
        spec.get("augmentation_policy")
    )
    overlap = set(trainer_args) & set(augmentation_args)
    if overlap:
        raise E1TrainingExperimentInputError(
            "duplicate_training_arg",
            "Trainer and augmentation arguments overlap: " + ", ".join(sorted(overlap)),
        )

    export_manifest_path = export_dir / "export_manifest.json"
    dataset_yaml = export_dir / "dataset.yaml"
    if not export_manifest_path.is_file() or not dataset_yaml.is_file():
        raise E1TrainingExperimentInputError(
            "invalid_export_package",
            "Training export must contain export_manifest.json and dataset.yaml.",
        )
    if export_manifest_path.stat().st_size <= 0 or dataset_yaml.stat().st_size <= 0:
        raise E1TrainingExperimentInputError(
            "empty_export_metadata",
            "Training export metadata files must be non-empty.",
        )
    export_manifest = _read_json_object(
        export_manifest_path, code_prefix="export_manifest"
    )
    dataset_id, dataset_version, class_map = _validate_export_manifest(
        export_manifest, expected_role=role
    )

    argv = [
        "yolo",
        "detect",
        "train",
        f"model={checkpoint}",
        f"data={dataset_yaml}",
        f"project={project_dir}",
        f"name={experiment_id}",
        "exist_ok=false",
        f"seed={seed}",
    ]
    for key in sorted(trainer_args):
        argv.append(f"{key}={_normalized_arg_value(trainer_args[key])}")
    for key in sorted(augmentation_args):
        argv.append(f"{key}={_normalized_arg_value(augmentation_args[key])}")

    return {
        "plan_schema_version": E1_TRAINING_PLAN_SCHEMA_VERSION,
        "experiment_schema_version": E1_TRAINING_EXPERIMENT_SCHEMA_VERSION,
        "experiment_id": experiment_id,
        "framework": framework,
        "framework_version": framework_version,
        "task": task,
        "model_role": role,
        "dataset": {
            "dataset_id": dataset_id,
            "dataset_version": dataset_version,
            "export_dir": str(export_dir),
            "dataset_yaml": str(dataset_yaml),
            "dataset_yaml_sha256": _sha256_file(dataset_yaml),
            "export_manifest": str(export_manifest_path),
            "export_manifest_sha256": _sha256_file(export_manifest_path),
            "class_map": class_map,
        },
        "checkpoint": {
            "path": str(checkpoint),
            "sha256": _sha256_file(checkpoint),
            "size_bytes": checkpoint.stat().st_size,
        },
        "seed": seed,
        "project_dir": str(project_dir),
        "run_dir": str(run_dir),
        "trainer_args": dict(sorted(trainer_args.items())),
        "augmentation_policy": {
            "mode": augmentation_mode,
            "args": dict(sorted(augmentation_args.items())),
        },
        "command_argv": argv,
        "execution_status": "not_executed",
    }


def materialize_training_plan(
    spec_path: Path,
    export_dir: Path,
    output_plan: Path,
) -> dict[str, Any]:
    output_plan = output_plan.resolve()
    if output_plan.exists():
        raise E1TrainingExperimentInputError(
            "output_plan_exists",
            f"Refusing to overwrite existing training plan: {output_plan}",
        )
    plan = build_training_plan(spec_path, export_dir)
    output_plan.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(plan, indent=2, sort_keys=True) + "\n"
    try:
        with output_plan.open("x", encoding="utf-8") as handle:
            handle.write(payload)
    except OSError as exc:
        raise E1TrainingExperimentInputError(
            "plan_write_error", f"Could not write {output_plan}: {exc}"
        ) from exc
    return {
        "ok": True,
        "output_plan": str(output_plan),
        "experiment_id": plan["experiment_id"],
        "model_role": plan["model_role"],
        "dataset_id": plan["dataset"]["dataset_id"],
        "dataset_version": plan["dataset"]["dataset_version"],
        "framework": plan["framework"],
        "framework_version": plan["framework_version"],
        "execution_status": "not_executed",
        "issues": [],
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m ai_runtime.e1_training_experiment",
        description="Build a reproducible, non-executing E1 YOLO training plan.",
    )
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON status.")
    parser.add_argument("--spec", required=True, type=Path)
    parser.add_argument("--export", required=True, dest="export_dir", type=Path)
    parser.add_argument("--output-plan", required=True, type=Path)
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    output = stdout if stdout is not None else sys.stdout
    try:
        result = materialize_training_plan(
            args.spec, args.export_dir, args.output_plan
        )
    except E1TrainingExperimentInputError as exc:
        result = {
            "ok": False,
            "output_plan": str(args.output_plan),
            "execution_status": "not_executed",
            "issues": [{"code": exc.code, "path": "$", "message": exc.message}],
        }
    json.dump(result, output, indent=2 if args.pretty else None, sort_keys=True)
    output.write("\n")
    output.flush()
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
