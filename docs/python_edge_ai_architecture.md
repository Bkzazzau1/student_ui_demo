# Python edge AI architecture

The Python runtime is the local reasoning layer, not the device authority.

```text
Dart UI and sensors -> normalized events -> Python review engine
        ^                                      |
        |                                      v
        +-------- Rust validates and executes proposed actions
                   and owns durable encrypted evidence
```

## Trust boundaries

- Dart owns presentation, consent, and platform lifecycle integration.
- Python receives metadata events and returns scores, reasons, and proposed actions.
- Rust decides whether a proposed action is permitted and performs device or evidence operations.
- A model output cannot directly fail a student or declare cheating.
- Raw camera/audio data should remain in the Rust-managed local evidence vault. Python receives derived signals unless a separately consented model explicitly requires a frame.
- Attempt memory is bounded and can be erased using `clear_attempt`.

## Integration sequence

1. Package Python and selected local models for each supported desktop platform.
2. Start `python -m ai_runtime` as a supervised child process.
3. Perform a `health` request and verify protocol version `1.0`.
4. Send normalized events from `LiveProctoringEvent` using `review_event`.
5. Pass every `proposed_actions` item to a Rust allow-list before execution.
6. Persist the returned reasons with evidence so human reviewers can audit decisions.

The current deterministic engine is deliberately small. It establishes the stable safety and IPC contract; local ONNX or PyTorch models can later be adapters behind `EdgeAiEngine` without granting Python additional device permissions.

The Dart process client is implemented in `lib/proctoring_demo/python_edge_ai_service.dart`.
The Rust authority is implemented in `native/brain_core/src/api/ai_action_policy.rs`.
The enforced orchestration path is implemented in
`lib/proctoring_demo/edge_ai_review_coordinator.dart`. Its startup fallback
denies every action if Rust authorization is unavailable.
`lib/proctoring_demo/native_edge_ai_action_authorizer.dart` is the production
adapter for the generated Rust binding and also fails closed on initialization
or native-call errors.
Regenerate the `flutter_rust_bridge` Dart bindings after installing the Rust/FRB
toolchain so Dart can invoke `authorize_ai_action` before executing proposals.
