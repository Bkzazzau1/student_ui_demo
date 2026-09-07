# Edge AI ModelEventV1 Contract

Status: **Frozen foundation for Stage 3 v1.1 implementation**

Schema version: `1.0`

## Purpose

`ModelEventV1` is the language-neutral observation envelope shared by specialist AI producers and the native temporal/evidence runtime. It preserves the original capture time of evidence so asynchronous, multi-rate inference can be aligned correctly.

It is an observation contract. It is **not** an accusation, policy decision, or final risk score.

## Frozen core fields

Every serialized event contains all of the following keys. Unknown optional evidence is represented as `null`; producers must not invent values to satisfy the schema.

| Field | Type | Required key | Nullable | Meaning |
|---|---|---:|---:|---|
| `schema_version` | string | yes | no | Contract version; currently `1.0` |
| `session_id` | string | yes | no | Exam/session boundary |
| `event_id` | string | yes | no | Unique event identifier within the runtime |
| `source_frame_id` | unsigned integer | yes | yes | Original source frame/sequence where applicable |
| `capture_timestamp_ns` | unsigned integer | yes | no | Process-monotonic time when source evidence was captured |
| `inference_timestamp_ns` | unsigned integer | yes | no | Process-monotonic time when inference completed |
| `model_id` | string | yes | no | Specialist producer/runtime ID |
| `model_version` | string | yes | no | Version of the producer/model |
| `track_id` | string | yes | yes | Persistent entity/person/object track where available |
| `class_id` | string | yes | no | Observable class/state emitted by the producer |
| `confidence` | number [0,1] | yes | yes | Calibrated/model confidence where available |
| `quality` | number [0,1] | yes | yes | Input/output signal quality where available |
| `geometry` | object | yes | yes | Spatial evidence where applicable |
| `validity_interval` | object | yes | no | Time interval for which this observation is considered valid |
| `metadata` | object | yes | no | Backward-compatible specialist measurements/extensions |

## Time semantics

`capture_timestamp_ns` is the temporal-alignment authority.

An inference result that completes later still belongs to the original source capture time. `inference_timestamp_ns` exists separately for latency, scheduling, health, and stale-result analysis.

Rules:

- `inference_timestamp_ns >= capture_timestamp_ns`.
- `validity_interval.end_timestamp_ns`, when known, must be `>= start_timestamp_ns`.
- Wall-clock `DateTime` values may be retained separately for logs/UI, but must not replace the common process-monotonic timebase for fusion.
- All modalities and deterministic system producers should use the same process-local monotonic timebase during an exam-client lifetime.

## Geometry v1

`geometry` may contain:

- `coordinate_space`: for example `normalized_frame` or `pixel_frame`;
- `bounding_box`: `{x, y, width, height}`;
- `keypoints`: list of `{x, y, confidence, label}`;
- `vector`: model-specific numerical vector such as gaze/pose direction;
- `region_id`: named exam-relative region where available.

Missing geometry is `null`. Missing categorical evidence is not interpolated into a class.

## Unknown preservation

The runtime preserves uncertainty explicitly:

- no source frame -> `source_frame_id: null`;
- no established track -> `track_id: null`;
- confidence not meaningful/available -> `confidence: null`;
- quality not measured -> `quality: null`;
- no spatial evidence -> `geometry: null`.

`null` means unknown/not applicable. It must not be silently converted to zero confidence, a synthetic track, or a fabricated spatial state.

## Model and deterministic producers

The same envelope is intended for E1-E8 model observations and deterministic system telemetry before E9 correlation.

For deterministic telemetry:

- `model_id` identifies the trusted native/system producer;
- `source_frame_id`, `track_id`, and `geometry` may legitimately be `null`;
- `class_id` carries the deterministic event/state class;
- `metadata` carries bounded supporting measurements/state transitions.

## Rust ownership

The production shared spatiotemporal memory is owned by Rust.

`SpatiotemporalRingBufferV1`:

- is session-scoped;
- is capacity-bounded;
- rejects duplicate event IDs;
- orders evidence by `capture_timestamp_ns`, not inference completion;
- retains validity intervals;
- permits multi-rate time-window queries;
- does not fabricate missing categorical states.

This is the foundation for the later Rust Evidence Graph and `Rp + Rd + Rc` risk runtime.

## Python ownership

Python owns AI/model engineering and may emit/consume the same `ModelEventV1` representation for model development, learned temporal models, calibration, and runtime specialist inference.

The Python and Rust representations must remain contract-compatible.

## Serialization

JSON is the v1 observability/development representation and is used for tests, logging, inspection, and transitional IPC.

High-frequency production IPC should later use a compact versioned binary representation (for example Protocol Buffers or FlatBuffers) without changing the semantic field contract.

## Compatibility policy

- `1.0.x`: implementation/validation fixes that do not change semantic fields.
- `1.x`: compatible extensions placed in `metadata` or explicitly versioned geometry additions.
- `2.0`: incompatible contract redesign.

Core fields must not be casually renamed or removed after this freeze.
