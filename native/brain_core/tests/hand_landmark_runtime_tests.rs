use brain_core::api::load_hand_landmark_model;

#[test]
fn hand_landmark_model_loads_from_assets() {
    let manifest = std::fs::read_to_string("../../assets/models/hand_landmark/manifest.json")
        .expect("hand landmark manifest should be readable");
    let model = std::fs::read("../../assets/models/hand_landmark/hand_landmark.onnx")
        .expect("hand landmark model should be readable");

    let status = load_hand_landmark_model(manifest, model);
    assert!(status.loaded, "{}", status.message);
}
