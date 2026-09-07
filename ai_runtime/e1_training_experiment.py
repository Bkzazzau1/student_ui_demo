"""Validate and lock reproducible E1 training experiment specifications.

Development-time tooling only. This module does not train a model and is never a
live exam dependency. Its job is to bind explicit experiment choices to one
verified E1 training export so later training can be reproduced and audited.
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
from .e1_training_readiness import E1_TAXONOMY_VERSION, ValidationIssue


E1_TRAINING_EXPERIMENT_SCHEMA_VERSION = "1.0"
E1_TRAINING_EXPERIMENT_LOCK_SCHEMA_VERSION = "1.0"
_ALLOWED_ROLES = frozenset({"base", "specialist"})
_ALLOWED_INITIALIZATION = frozenset({"scratch", "pretrained"})
_ALLOWED_PRECISION = frozenset({"fp32", "amp"})
_REQUIRED_TRAINING_FIELDS = (
    "seed",
    "image_size",
    "epochs",
    "batch_size",
    "optimizer",
    "learning_rate",
    "weight_decay",
    "workers",
    "precision",
    "deterministic",
)


class E1TrainingExperimentInputError(ValueError):
    """Raised when experiment locking cannot proceed safely."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _issue(code: str, path: str, message: str) -> ValidationIssue:
    return ValidationIssue(code=code, path=path, message=message)


def _read_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _read_lower_string(value: Any) -> str:
    return _read_string(value).lower()


def _finite_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    return numeric if math.isfinite(numeric) else None


def _positive_int(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        return None
    return value


def _non_negative_int(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return None
    return value


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_json_object(path: Path, *, code_prefix: str) -> Mapping[str, Any]:
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


def _validate_image_size(value: Any, path: str) -> list[ValidationIssue]:
    if isinstance(value, bool):
        return [_issue("invalid_image_size", path, "image_size must be a positive integer or [width, height].")]
    if isinstance(value, int):
        return [] if value > 0 else [
            _issue("invalid_image_size", path, "image_size must be positive.")
        ]
    if (
        isinstance(value, Sequence)
        and not isinstance(value, (str, bytes))
        and len(value) == 2
        and all(_positive_int(item) is not None for item in value)
    ):
        return []
    return [
        _issue(
            "invalid_image_size",
            path,
            "image_size must be a positive integer or a two-item [width, height] list.",
        )
    ]


def validate_experiment_spec(spec: Mapping[str, Any]) -> tuple[ValidationIssue, ...]:
    """Validate one explicit training experiment specification.

    There are deliberately no training defaults. Missing scientific choices are
    validation errors rather than being silently supplied by this module.
    """

    issues: list[ValidationIssue] = []
    if _read_string(spec.get("experiment_schema_version")) != E1_TRAINING_EXPERIMENT_SCHEMA_VERSION:
        issues.append(
            _issue(
                "invalid_experiment_schema_version",
                "experiment_schema_version",
                f"experiment_schema_version must be {E1_TRAINING_EXPERIMENT_SCHEMA_VERSION}.",
            )
        )
    if not _read_string(spec.get("experiment_id")):
        issues.append(_issue("missing_experiment_id", "experiment_id", "experiment_id is required."))

    role = _read_lower_string(spec.get("model_role"))
    if role not in _ALLOWED_ROLES:
        issues.append(
            _issue("invalid_model_role", "model_role", "model_role must be 'base' or 'specialist'.")
        )

    framework = spec.get("framework")
    if not isinstance(framework, Mapping):
        issues.append(_issue("invalid_framework", "framework", "framework must be an object."))
    else:
        if not _read_string(framework.get("name")):
            issues.append(_issue("missing_framework_name", "framework.name", "framework.name is required."))
        if not _read_string(framework.get("version")):
            issues.append(
                _issue("missing_framework_version", "framework.version", "framework.version is required.")
            )

    model = spec.get("model")
    if not isinstance(model, Mapping):
        issues.append(_issue("invalid_model", "model", "model must be an object."))
    else:
        if not _read_string(model.get("architecture")):
            issues.append(
                _issue("missing_model_architecture", "model.architecture", "model.architecture is required.")
            )
        initialization = _read_lower_string(model.get("initialization"))
        if initialization not in _ALLOWED_INITIALIZATION:
            issues.append(
                _issue(
                    "invalid_model_initialization",
                    "model.initialization",
                    "model.initialization must be 'scratch' or 'pretrained'.",
                )
            )
        checkpoint = model.get("checkpoint")
        if initialization == "scratch":
            if checkpoint is not None:
                issues.append(
                    _issue(
                        "scratch_checkpoint_must_be_null",
                        "model.checkpoint",
                        "Scratch initialization must use checkpoint: null.",
                    )
                )
        elif initialization == "pretrained":
            if not isinstance(checkpoint, Mapping):
                issues.append(
                    _issue(
                        "missing_pretrained_checkpoint",
                        "model.checkpoint",
                        "Pretrained initialization requires a checkpoint object.",
                    )
                )
            else:
                if not _read_string(checkpoint.get("path")):
                    issues.append(
                        _issue(
                            "missing_checkpoint_path",
                            "model.checkpoint.path",
                            "Pretrained checkpoint path is required.",
                        )
                    )
                sha = _read_lower_string(checkpoint.get("sha256"))
                if len(sha) != 64 or any(character not in "0123456789abcdef" for character in sha):
                    issues.append(
                        _issue(
                            "invalid_checkpoint_sha256",
                            "model.checkpoint.sha256",
                            "Checkpoint SHA-256 must be exactly 64 lowercase hexadecimal characters.",
                        )
                    )

    training = spec.get("training")
    if not isinstance(training, Mapping):
        issues.append(_issue("invalid_training", "training", "training must be an object."))
    else:
        for field in _REQUIRED_TRAINING_FIELDS:
            if field not in training:
                issues.append(
                    _issue(
                        "missing_training_field",
                        f"training.{field}",
                        f"training.{field} must be supplied explicitly; no default is assumed.",
                    )
                )
        if "seed" in training and _non_negative_int(training.get("seed")) is None:
            issues.append(_issue("invalid_seed", "training.seed", "training.seed must be a non-negative integer."))
        if "image_size" in training:
            issues.extend(_validate_image_size(training.get("image_size"), "training.image_size"))
        if "epochs" in training and _positive_int(training.get("epochs")) is None:
            issues.append(_issue("invalid_epochs", "training.epochs", "training.epochs must be a positive integer."))
        if "batch_size" in training and _positive_int(training.get("batch_size")) is None:
            issues.append(
                _issue("invalid_batch_size", "training.batch_size", "training.batch_size must be a positive integer.")
            )
        if "optimizer" in training and not _read_string(training.get("optimizer")):
            issues.append(_issue("invalid_optimizer", "training.optimizer", "training.optimizer is required."))
        if "learning_rate" in training:
            value = _finite_number(training.get("learning_rate"))
            if value is None or value <= 0:
                issues.append(
                    _issue(
                        "invalid_learning_rate",
                        "training.learning_rate",
                        "training.learning_rate must be a finite positive number.",
                    )
                )
        if "weight_decay" in training:
            value = _finite_number(training.get("weight_decay"))
            if value is None or value < 0:
                issues.append(
                    _issue(
                        "invalid_weight_decay",
                        "training.weight_decay",
                        "training.weight_decay must be a finite non-negative number.",
                    )
                )
        if "workers" in training and _non_negative_int(training.get("workers")) is None:
            issues.append(_issue("invalid_workers", "training.workers", "training.workers must be a non-negative integer."))
        if "precision" in training and _read_lower_string(training.get("precision")) not in _ALLOWED_PRECISION:
            issues.append(
                _issue(
                    "invalid_precision",
                    "training.precision",
                    "training.precision must be 'fp32' or 'amp'.",
                )
            )
        if "deterministic" in training and not isinstance(training.get("deterministic"), bool):
            issues.append(
                _issue(
                    "invalid_deterministic_flag",
                    "training.deterministic",
                    "training.deterministic must be boolean.",
                )
            )

    augmentation = spec.get("augmentation")
    if not isinstance(augmentation, Mapping):
        issues.append(_issue("invalid_augmentation", "augmentation", "augmentation must be an object."))
    else:
        if not isinstance(augmentation.get("enabled"), bool):
            issues.append(
                _issue("invalid_augmentation_enabled", "augmentation.enabled", "augmentation.enabled must be boolean.")
            )
        parameters = augmentation.get("parameters")
        if not isinstance(parameters, Mapping):
            issues.append(
                _issue(
                    "invalid_augmentation_parameters",
                    "augmentation.parameters",
                    "augmentation.parameters must be an explicit object, even when empty.",
                )
            )

    execution = spec.get("execution")
    if not isinstance(execution, Mapping):
        issues.append(_issue("invalid_execution", "execution", "execution must be an object."))
    else:
        if not _read_string(execution.get("device")):
            issues.append(_issue("missing_execution_device", "execution.device", "execution.device is required."))

    return tuple(issues)


def _safe_export_relative_path(value: Any) -> Path | None:
    raw = _read_string(value).replace("\\", "/")
    if not raw:
        return None
    path = Path(raw)
    if path.is_absolute() or ".." in path.parts:
        return None
    return path


def _verify_export_package(export_dir: Path, role: str) -> dict[str, Any]:
    export_manifest_path = export_dir / "export_manifest.json"
    dataset_yaml_path = export_dir / "dataset.yaml"
    if not export_manifest_path.is_file() or not dataset_yaml_path.is_file():
        raise E1TrainingExperimentInputError(
            "incomplete_training_export",
            "Training export must contain export_manifest.json and dataset.yaml.",
        )

    export_manifest = _load_json_object(export_manifest_path, code_prefix="export_manifest")
    if _read_string(export_manifest.get("export_schema_version")) != E1_TRAINING_EXPORT_SCHEMA_VERSION:
        raise E1TrainingExperimentInputError(
            "invalid_export_schema_version",
            f"export_manifest.json must use export schema {E1_TRAINING_EXPORT_SCHEMA_VERSION}.",
        )
    if _read_string(export_manifest.get("taxonomy_version")) != E1_TAXONOMY_VERSION:
        raise E1TrainingExperimentInputError(
            "invalid_export_taxonomy_version",
            f"Training export must use E1 taxonomy {E1_TAXONOMY_VERSION}.",
        )
    export_role = _read_lower_string(export_manifest.get("model_role"))
    if export_role != role:
        raise E1TrainingExperimentInputError(
            "experiment_export_role_mismatch",
            f"Experiment role {role!r} does not match export role {export_role!r}.",
        )

    expected_class_order = class_order_for_role(role)
    class_map = export_manifest.get("class_map")
    if not isinstance(class_map, Sequence) or isinstance(class_map, (str, bytes)):
        raise E1TrainingExperimentInputError(
            "invalid_export_class_map", "export_manifest.json class_map must be a list."
        )
    actual_class_order: list[str] = []
    for expected_index, item in enumerate(class_map):
        if not isinstance(item, Mapping) or item.get("index") != expected_index:
            raise E1TrainingExperimentInputError(
                "invalid_export_class_map",
                "Training export class_map indices must be contiguous and ordered.",
            )
        actual_class_order.append(_read_string(item.get("canonical_object_id")))
    if tuple(actual_class_order) != expected_class_order:
        raise E1TrainingExperimentInputError(
            "export_class_order_mismatch",
            "Training export class order does not match the frozen E1 role order.",
        )

    samples = export_manifest.get("samples")
    if not isinstance(samples, Sequence) or isinstance(samples, (str, bytes)):
        raise E1TrainingExperimentInputError(
            "invalid_export_samples", "export_manifest.json samples must be a list."
        )

    package_paths: set[Path] = {Path("dataset.yaml"), Path("export_manifest.json")}
    verified_samples = 0
    for item in samples:
        if not isinstance(item, Mapping):
            raise E1TrainingExperimentInputError(
                "invalid_export_sample", "Every export sample record must be an object."
            )
        image_rel = _safe_export_relative_path(item.get("export_image_path"))
        label_rel = _safe_export_relative_path(item.get("export_label_path"))
        if image_rel is None or label_rel is None:
            raise E1TrainingExperimentInputError(
                "unsafe_export_path", "Exported image and label paths must stay inside the export directory."
            )
        image_path = export_dir / image_rel
        label_path = export_dir / label_rel
        if not image_path.is_file() or not label_path.is_file():
            raise E1TrainingExperimentInputError(
                "missing_export_artifact",
                f"Export sample artifacts are missing for {item.get('sample_id')!r}.",
            )
        expected_image_sha = _read_lower_string(item.get("source_image_sha256"))
        actual_image_sha = _sha256_file(image_path)
        if actual_image_sha != expected_image_sha:
            raise E1TrainingExperimentInputError(
                "export_image_hash_mismatch",
                f"Exported image bytes do not match recorded source SHA-256 for {item.get('sample_id')!r}.",
            )
        package_paths.add(image_rel)
        package_paths.add(label_rel)
        verified_samples += 1

    package_digest = hashlib.sha256()
    file_records = []
    for relative_path in sorted(package_paths, key=lambda path: path.as_posix()):
        full_path = export_dir / relative_path
        file_sha = _sha256_file(full_path)
        relative_text = relative_path.as_posix()
        package_digest.update(relative_text.encode("utf-8"))
        package_digest.update(b"\0")
        package_digest.update(file_sha.encode("ascii"))
        package_digest.update(b"\n")
        file_records.append({"path": relative_text, "sha256": file_sha})

    return {
        "dataset_id": _read_string(export_manifest.get("dataset_id")),
        "dataset_version": _read_string(export_manifest.get("dataset_version")),
        "model_role": export_role,
        "taxonomy_version": E1_TAXONOMY_VERSION,
        "export_schema_version": E1_TRAINING_EXPORT_SCHEMA_VERSION,
        "export_manifest_sha256": _sha256_file(export_manifest_path),
        "dataset_yaml_sha256": _sha256_file(dataset_yaml_path),
        "package_sha256": package_digest.hexdigest(),
        "verified_sample_count": verified_samples,
        "files": file_records,
    }


def _resolve_declared_file(spec_path: Path, declared_path: str) -> Path:
    path = Path(declared_path)
    if path.is_absolute():
        return path
    return (spec_path.parent / path).resolve()


def lock_training_experiment(
    spec_path: Path,
    export_dir: Path,
    output_path: Path,
) -> dict[str, Any]:
    """Validate an explicit experiment and write an immutable experiment lock."""

    if output_path.exists():
        raise E1TrainingExperimentInputError(
            "output_exists", f"Refusing to overwrite existing lock: {output_path}"
        )
    spec = _load_json_object(spec_path, code_prefix="experiment_spec")
    issues = validate_experiment_spec(spec)
    if issues:
        return {
            "ok": False,
            "issues": [
                {"code": issue.code, "path": issue.path, "message": issue.message}
                for issue in issues
            ],
        }

    role = _read_lower_string(spec.get("model_role"))
    dataset_lock = _verify_export_package(export_dir.resolve(), role)

    model = spec["model"]
    checkpoint_lock: dict[str, Any] | None = None
    if _read_lower_string(model.get("initialization")) == "pretrained":
        checkpoint = model["checkpoint"]
        declared_path = _read_string(checkpoint.get("path"))
        checkpoint_path = _resolve_declared_file(spec_path.resolve(), declared_path)
        if not checkpoint_path.is_file():
            raise E1TrainingExperimentInputError(
                "checkpoint_missing", f"Pretrained checkpoint does not exist: {checkpoint_path}"
            )
        expected_sha = _read_lower_string(checkpoint.get("sha256"))
        actual_sha = _sha256_file(checkpoint_path)
        if actual_sha != expected_sha:
            raise E1TrainingExperimentInputError(
                "checkpoint_hash_mismatch",
                "Pretrained checkpoint SHA-256 does not match the experiment specification.",
            )
        checkpoint_lock = {
            "declared_path": declared_path,
            "sha256": actual_sha,
        }

    lock = {
        "lock_schema_version": E1_TRAINING_EXPERIMENT_LOCK_SCHEMA_VERSION,
        "experiment": spec,
        "dataset": dataset_lock,
        "checkpoint": checkpoint_lock,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {
        "ok": True,
        "output": str(output_path),
        "experiment_id": _read_string(spec.get("experiment_id")),
        "model_role": role,
        "dataset_package_sha256": dataset_lock["package_sha256"],
        "checkpoint_sha256": checkpoint_lock["sha256"] if checkpoint_lock else None,
        "issues": [],
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m ai_runtime.e1_training_experiment",
        description="Lock an explicit E1 training experiment to one verified training export.",
    )
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON status output.")
    parser.add_argument("--export", required=True, type=Path, help="Validated E1 training export directory.")
    parser.add_argument("--output", required=True, type=Path, help="New experiment lock JSON path.")
    parser.add_argument("spec", type=Path, help="Explicit experiment specification JSON.")
    return parser


def main(argv: Sequence[str] | None = None, *, stdout: TextIO | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    output = stdout if stdout is not None else sys.stdout
    try:
        result = lock_training_experiment(args.spec, args.export, args.output)
    except E1TrainingExperimentInputError as exc:
        result = {
            "ok": False,
            "issues": [{"code": exc.code, "path": "$", "message": exc.message}],
        }
    json.dump(result, output, indent=2 if args.pretty else None, sort_keys=True)
    output.write("\n")
    output.flush()
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
