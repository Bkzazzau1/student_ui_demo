use brain_core::api::analyze_audio_pcm16;

fn pcm16_bytes(samples: &[i16]) -> Vec<u8> {
    let mut bytes = Vec::<u8>::with_capacity(samples.len() * 2);
    for sample in samples {
        bytes.extend_from_slice(&sample.to_le_bytes());
    }
    bytes
}

#[test]
fn rejects_empty_audio() {
    let result = analyze_audio_pcm16(Vec::new(), 44_100, None);
    assert!(result.is_none());
}

#[test]
fn recognises_low_ambient_audio() {
    let samples = vec![80_i16; 512];
    let result = analyze_audio_pcm16(pcm16_bytes(&samples), 44_100, None)
        .expect("audio result");

    assert!(result.ready);
    assert!(result.allowed_ambient_likely);
    assert!(!result.near_voice_likely);
}

#[test]
fn recognises_voice_like_audio() {
    let mut samples = Vec::<i16>::new();
    for i in 0..2048 {
        let value = if i % 8 < 4 { 9000_i16 } else { -7000_i16 };
        samples.push(value);
    }
    let result = analyze_audio_pcm16(pcm16_bytes(&samples), 44_100, None)
        .expect("audio result");

    assert!(result.ready);
    assert!(result.voice_confidence >= 0.46);
    assert!(result.near_voice_likely || result.possible_far_voice_likely);
}

#[test]
fn detects_repeated_fingerprint() {
    let mut samples = Vec::<i16>::new();
    for i in 0..1024 {
        samples.push(if i % 2 == 0 { 3000_i16 } else { -3000_i16 });
    }
    let first = analyze_audio_pcm16(pcm16_bytes(&samples), 44_100, None)
        .expect("first result");
    let second = analyze_audio_pcm16(
        pcm16_bytes(&samples),
        44_100,
        Some(first.fingerprint.clone()),
    )
    .expect("second result");

    assert_eq!(first.fingerprint, second.fingerprint);
    assert!(second.repeated_fingerprint);
}
