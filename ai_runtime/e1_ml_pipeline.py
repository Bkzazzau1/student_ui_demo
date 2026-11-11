"""Command line entrypoint for development-only E1 experiments."""

import argparse
import json
from pathlib import Path
import sys

from .e1_ml_common import load, save


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    tensors = commands.add_parser("prepare-tensors")
    tensors.add_argument("--manifest", required=True, type=Path)
    tensors.add_argument("--size", required=True, type=int)
    tensors.add_argument("--preprocessing", required=True, choices=("stretch_nn_rgb01",))
    tensors.add_argument("--output", required=True, type=Path)
    train = commands.add_parser("train")
    train.add_argument("--config", required=True, type=Path)
    train.add_argument("--package", required=True, type=Path)
    train.add_argument("--output", required=True, type=Path)
    export = commands.add_parser("export-onnx")
    export.add_argument("--checkpoint", required=True, type=Path)
    export.add_argument("--role", required=True, choices=("base", "specialist"))
    export.add_argument("--size", required=True, type=int)
    export.add_argument("--model-id", required=True)
    export.add_argument("--version", required=True)
    export.add_argument("--output", required=True, type=Path)
    evaluation = commands.add_parser("evaluate")
    evaluation.add_argument("--manifests", required=True, nargs="+", type=Path)
    evaluation.add_argument("--predictions", required=True, type=Path)
    evaluation.add_argument("--operating-confidence", required=True, type=float)
    evaluation.add_argument("--output", required=True, type=Path)
    calibration = commands.add_parser("ingest-calibration")
    calibration.add_argument("--report", required=True, type=Path)
    calibration.add_argument("--evidence", required=True, type=Path)
    calibration.add_argument("--manifests", required=True, nargs="+", type=Path)
    calibration.add_argument("--output", required=True, type=Path)
    for name in ("predict-tensors", "parity", "benchmark", "quantize"):
        command = commands.add_parser(name)
        command.add_argument("--model", required=True, type=Path)
        command.add_argument("--fixture", required=name != "quantize", type=Path)
        command.add_argument("--output", required=True, type=Path)
        if name in {"predict-tensors", "parity"}:
            command.add_argument("--metadata", required=True, type=Path)
            command.add_argument("--nms-iou", required=True, type=float)
        if name == "predict-tensors":
            command.add_argument("--manifest", required=True, type=Path)
            command.add_argument("--score-floor", required=True, type=float)
        if name == "parity":
            command.add_argument("--checkpoint", required=True, type=Path)
            command.add_argument("--atol", required=True, type=float)
            command.add_argument("--rtol", required=True, type=float)
            command.add_argument("--confidence", required=True, type=float)
        if name in {"predict-tensors", "benchmark"}:
            command.add_argument("--provider", required=True)
        if name == "benchmark":
            command.add_argument("--warmup", required=True, type=int)
            command.add_argument("--repeats", required=True, type=int)
        if name == "quantize":
            command.add_argument("--metadata", required=True, type=Path)
            command.add_argument("--precision", required=True, choices=("fp16", "int8"))
    candidate = commands.add_parser("manifest")
    for arg in ("metadata", "evaluation", "parity", "output"):
        candidate.add_argument(f"--{arg}", required=True, type=Path)
    scenarios = commands.add_parser("scenarios")
    for arg in ("spec", "trace", "output"):
        scenarios.add_argument(f"--{arg}", required=True, type=Path)
    return result


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if args.output.exists():
            raise ValueError("Refusing to overwrite an existing output")
        from . import e1_experiments as experiments
        if args.command == "prepare-tensors":
            from .e1_tensor_fixtures import prepare
            result = prepare(args.manifest, args.size, args.output)
        elif args.command == "train":
            result = experiments.train(load(args.config), args.package, args.output)
        elif args.command == "export-onnx":
            result = experiments.export_onnx(args.checkpoint, args.role, args.size,
                                              args.output, args.model_id, args.version)
        elif args.command == "quantize":
            from .e1_variants import quantize
            result = quantize(args.model, args.output, args.precision, args.fixture, load(args.metadata))
        else:
            if args.command == "evaluate":
                from .e1_evaluation import evaluate
                result = evaluate([load(p) for p in args.manifests], load(args.predictions), args.operating_confidence)
            elif args.command == "ingest-calibration":
                from .e1_evaluation import ingest_calibration
                result = ingest_calibration(load(args.report), load(args.evidence), [load(p) for p in args.manifests])
            elif args.command == "predict-tensors":
                from .e1_variants import predict_tensors
                result = predict_tensors(args.model, args.fixture, load(args.manifest),
                    load(args.metadata), args.score_floor, args.nms_iou, args.provider)
            elif args.command == "parity":
                result = experiments.parity(args.model, args.checkpoint, args.fixture,
                    load(args.metadata), args.atol, args.rtol, args.confidence, args.nms_iou)
            elif args.command == "benchmark":
                result = experiments.benchmark(args.model, args.fixture, args.provider, args.warmup, args.repeats)
            elif args.command == "manifest":
                result = experiments.candidate_manifest(load(args.metadata), load(args.evaluation), load(args.parity))
            else:
                from .e1_scenarios import check_scenarios
                result = check_scenarios(load(args.spec), load(args.trace))
            save(args.output, result)
        print(json.dumps(result, sort_keys=True, allow_nan=False))
        return 0 if result.get("evaluation_valid", True) else 1
    except Exception as exc:  # CLI boundary: framework failures are structured, nonzero results.
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
