use flutter_rust_bridge::frb;
use std::f64::consts::PI;

#[frb]
#[derive(Clone, Debug)]
pub struct NativeAudioIntelligenceResult {
    pub ready: bool,
    pub label: String,
    pub rms: f64,
    pub peak: f64,
    pub zero_crossing_rate: f64,
    pub dynamic_variation: f64,
    pub voice_confidence: f64,
    pub near_voice_likely: bool,
    pub possible_far_voice_likely: bool,
    pub allowed_ambient_likely: bool,
    pub repeated_fingerprint: bool,
    pub fingerprint: String,
}

#[frb(sync)]
pub fn analyze_audio_pcm16(
    bytes: Vec<u8>,
    sample_rate: i32,
    previous_fingerprint: Option<String>,
) -> Option<NativeAudioIntelligenceResult> {
    analyse_pcm16(&bytes, sample_rate, previous_fingerprint.as_deref())
}

fn analyse_pcm16(
    bytes: &[u8],
    sample_rate: i32,
    previous_fingerprint: Option<&str>,
) -> Option<NativeAudioIntelligenceResult> {
    if bytes.len() < 4 || sample_rate <= 0 {
        return None;
    }

    let raw_samples = decode_pcm16(bytes);
    if raw_samples.len() < 16 {
        return None;
    }

    let samples = raw_samples
        .iter()
        .map(|sample| *sample as f64 / 32768.0)
        .collect::<Vec<f64>>();
    let features = extract_features(&samples, sample_rate);
    let classification = classify_audio(&features);
    let fingerprint = make_fingerprint(&features, classification.voice_confidence);
    let repeated_fingerprint = previous_fingerprint
        .map(|previous| !previous.is_empty() && previous == fingerprint)
        .unwrap_or(false);

    Some(NativeAudioIntelligenceResult {
        ready: true,
        label: classification.label.to_string(),
        rms: features.rms,
        peak: features.peak,
        zero_crossing_rate: features.zero_crossing_rate,
        dynamic_variation: features.dynamic_variation,
        voice_confidence: classification.voice_confidence,
        near_voice_likely: classification.near_voice_likely,
        possible_far_voice_likely: classification.possible_far_voice_likely,
        allowed_ambient_likely: classification.allowed_ambient_likely,
        repeated_fingerprint,
        fingerprint,
    })
}

#[derive(Clone, Debug)]
struct AudioFeatures {
    rms: f64,
    peak: f64,
    zero_crossing_rate: f64,
    dynamic_variation: f64,
    slope_energy: f64,
    envelope_variation: f64,
    impulse_ratio: f64,
    low_band_energy: f64,
    hum_band_energy: f64,
    speech_band_energy: f64,
    high_band_energy: f64,
    tonal_score: f64,
}

#[derive(Clone, Debug)]
struct AudioClassification {
    label: &'static str,
    voice_confidence: f64,
    near_voice_likely: bool,
    possible_far_voice_likely: bool,
    allowed_ambient_likely: bool,
}

fn extract_features(samples: &[f64], sample_rate: i32) -> AudioFeatures {
    let mut sum_squares = 0.0_f64;
    let mut peak = 0.0_f64;
    let mut crossings = 0_i32;
    let mut slope_energy_sum = 0.0_f64;
    let mut previous = samples[0];

    for (index, value) in samples.iter().enumerate() {
        let abs = value.abs();
        peak = peak.max(abs);
        sum_squares += value * value;

        if index > 0 {
            if (previous < 0.0 && *value >= 0.0) || (previous >= 0.0 && *value < 0.0) {
                crossings += 1;
            }
            let diff = value - previous;
            slope_energy_sum += diff * diff;
        }
        previous = *value;
    }

    let sample_count = samples.len() as f64;
    let rms = (sum_squares / sample_count).sqrt().clamp(0.0, 1.0);
    let zero_crossing_rate = (crossings as f64 / sample_count).clamp(0.0, 1.0);
    let slope_energy = (slope_energy_sum / (sample_count - 1.0).max(1.0))
        .sqrt()
        .clamp(0.0, 1.0);
    let envelope_variation = envelope_variation(samples, sample_rate);
    let dynamic_variation = ((slope_energy * 0.70) + (envelope_variation * 0.30)).clamp(0.0, 1.0);
    let impulse_ratio = peak / rms.max(0.0008);

    let low_band_energy = band_energy(samples, sample_rate, &[80.0, 120.0, 180.0, 250.0]);
    let hum_band_energy = band_energy(samples, sample_rate, &[50.0, 60.0, 100.0, 120.0]);
    let speech_band_energy = band_energy(samples, sample_rate, &[300.0, 500.0, 800.0, 1200.0, 1800.0, 2600.0]);
    let high_band_energy = band_energy(samples, sample_rate, &[3500.0, 5200.0, 7000.0]);
    let tonal_score = tonal_score(
        samples,
        sample_rate,
        &[60.0, 120.0, 250.0, 500.0, 1000.0, 1500.0, 2000.0, 3000.0, 4200.0],
    );

    AudioFeatures {
        rms,
        peak,
        zero_crossing_rate,
        dynamic_variation,
        slope_energy,
        envelope_variation,
        impulse_ratio,
        low_band_energy,
        hum_band_energy,
        speech_band_energy,
        high_band_energy,
        tonal_score,
    }
}

fn classify_audio(features: &AudioFeatures) -> AudioClassification {
    let band_total = (features.low_band_energy
        + features.hum_band_energy
        + features.speech_band_energy
        + features.high_band_energy)
        .max(0.000_001);
    let low_ratio = (features.low_band_energy + features.hum_band_energy) / band_total;
    let speech_ratio = features.speech_band_energy / band_total;
    let high_ratio = features.high_band_energy / band_total;
    let speech_zcr = features.zero_crossing_rate >= 0.018 && features.zero_crossing_rate <= 0.36;
    let steady_envelope = features.envelope_variation <= (features.rms.max(0.001) * 0.24);
    let speech_texture = speech_zcr
        && (features.slope_energy >= 0.0025 || speech_ratio >= 0.26 || high_ratio >= 0.18)
        && !steady_envelope;
    let impulse_like = features.impulse_ratio >= 7.5 && features.peak >= 0.08;
    let tonal_like = features.tonal_score >= 0.42;

    let mut voice_confidence = 0.0_f64;
    if features.rms >= 0.004 && features.rms <= 0.65 {
        voice_confidence += 0.12;
    }
    if features.peak >= 0.025 {
        voice_confidence += 0.14;
    }
    if speech_zcr {
        voice_confidence += 0.18;
    }
    if speech_texture {
        voice_confidence += 0.24;
    }
    if speech_ratio >= 0.22 {
        voice_confidence += 0.18;
    }
    if high_ratio >= 0.16 && features.rms < 0.045 {
        voice_confidence += 0.08;
    }
    if features.dynamic_variation >= 0.004 {
        voice_confidence += 0.08;
    }
    if steady_envelope && low_ratio >= 0.45 {
        voice_confidence -= 0.18;
    }
    if impulse_like {
        voice_confidence -= 0.10;
    }
    if tonal_like && speech_ratio < 0.36 {
        voice_confidence -= 0.10;
    }
    voice_confidence = voice_confidence.clamp(0.0, 1.0);

    let quiet = features.rms < 0.005 && features.peak < 0.035;
    let phone_ringtone = tonal_like
        && features.rms >= 0.010
        && features.peak >= 0.040
        && (speech_ratio >= 0.22 || high_ratio >= 0.20)
        && features.impulse_ratio < 7.0;
    let keyboard_or_typing = impulse_like && features.rms <= 0.070 && high_ratio >= 0.10;
    let whisper_or_low_voice = !phone_ringtone
        && !keyboard_or_typing
        && voice_confidence >= 0.40
        && features.rms < 0.020
        && (high_ratio >= 0.16 || speech_ratio >= 0.24);
    let near_voice = !phone_ringtone
        && !keyboard_or_typing
        && voice_confidence >= 0.62
        && features.rms >= 0.018
        && features.peak >= 0.075;
    let possible_multiple_voices = near_voice
        && features.dynamic_variation >= 0.045
        && speech_ratio >= 0.24
        && features.peak >= 0.12;
    let far_voice = !near_voice
        && !whisper_or_low_voice
        && !phone_ringtone
        && voice_confidence >= 0.46
        && features.rms >= 0.007
        && features.peak >= 0.035;
    let fan_ambient = !near_voice
        && !far_voice
        && !whisper_or_low_voice
        && !phone_ringtone
        && steady_envelope
        && low_ratio >= 0.42
        && features.rms >= 0.005;
    let generator_or_engine = !near_voice
        && !far_voice
        && !whisper_or_low_voice
        && !phone_ringtone
        && low_ratio >= 0.46
        && features.rms >= 0.012
        && features.tonal_score >= 0.22;
    let vehicle_or_motorcycle = !near_voice
        && !far_voice
        && !whisper_or_low_voice
        && !phone_ringtone
        && features.rms >= 0.018
        && low_ratio >= 0.32
        && features.dynamic_variation >= 0.010;

    if quiet {
        return classification("quiet_or_low_noise", voice_confidence, false, false, true);
    }
    if phone_ringtone {
        return classification("phone_ringtone_like_sound", voice_confidence, false, false, false);
    }
    if keyboard_or_typing {
        return classification("keyboard_or_tapping_sound", voice_confidence, false, false, false);
    }
    if possible_multiple_voices {
        return classification("possible_multiple_voices", voice_confidence, true, false, false);
    }
    if near_voice {
        return classification("near_voice", voice_confidence, true, false, false);
    }
    if whisper_or_low_voice {
        return classification("whisper_or_low_voice", voice_confidence, false, true, false);
    }
    if far_voice {
        return classification("far_or_background_voice", voice_confidence, false, true, false);
    }
    if fan_ambient {
        return classification("fan_ambient_sound", voice_confidence, false, false, true);
    }
    if generator_or_engine {
        return classification("generator_or_engine_ambient", voice_confidence, false, false, features.rms < 0.060);
    }
    if vehicle_or_motorcycle {
        return classification("vehicle_or_motorcycle_ambient", voice_confidence, false, false, false);
    }

    classification("unclear_environment_sound", voice_confidence, false, false, features.rms < 0.012)
}

fn classification(
    label: &'static str,
    voice_confidence: f64,
    near_voice_likely: bool,
    possible_far_voice_likely: bool,
    allowed_ambient_likely: bool,
) -> AudioClassification {
    AudioClassification {
        label,
        voice_confidence: voice_confidence.clamp(0.0, 1.0),
        near_voice_likely,
        possible_far_voice_likely,
        allowed_ambient_likely,
    }
}

fn envelope_variation(samples: &[f64], sample_rate: i32) -> f64 {
    if samples.is_empty() {
        return 0.0;
    }

    let frame_size = ((sample_rate.max(1) as usize) / 50).max(32).min(samples.len());
    if frame_size == 0 {
        return 0.0;
    }

    let mut frames = Vec::<f64>::new();
    for frame in samples.chunks(frame_size) {
        let sum = frame.iter().fold(0.0_f64, |acc, value| acc + value * value);
        frames.push((sum / frame.len().max(1) as f64).sqrt());
    }

    if frames.len() < 2 {
        return 0.0;
    }

    let mut total = 0.0_f64;
    for index in 1..frames.len() {
        total += (frames[index] - frames[index - 1]).abs();
    }
    (total / (frames.len() - 1) as f64).clamp(0.0, 1.0)
}

fn band_energy(samples: &[f64], sample_rate: i32, frequencies: &[f64]) -> f64 {
    if samples.is_empty() || frequencies.is_empty() {
        return 0.0;
    }

    let mut total = 0.0_f64;
    let mut count = 0.0_f64;
    for frequency in frequencies {
        if *frequency > 0.0 && *frequency < (sample_rate as f64 / 2.0) {
            total += goertzel_power(samples, sample_rate, *frequency);
            count += 1.0;
        }
    }

    if count <= 0.0 {
        0.0
    } else {
        (total / count).clamp(0.0, 1.0)
    }
}

fn tonal_score(samples: &[f64], sample_rate: i32, frequencies: &[f64]) -> f64 {
    let mut total = 0.0_f64;
    let mut peak = 0.0_f64;
    for frequency in frequencies {
        if *frequency > 0.0 && *frequency < (sample_rate as f64 / 2.0) {
            let power = goertzel_power(samples, sample_rate, *frequency);
            total += power;
            peak = peak.max(power);
        }
    }

    if total <= 0.000_001 {
        0.0
    } else {
        (peak / total).clamp(0.0, 1.0)
    }
}

fn goertzel_power(samples: &[f64], sample_rate: i32, frequency: f64) -> f64 {
    if samples.is_empty() || sample_rate <= 0 || frequency <= 0.0 {
        return 0.0;
    }

    let normalized_frequency = frequency / sample_rate as f64;
    if normalized_frequency >= 0.5 {
        return 0.0;
    }

    let omega = 2.0 * PI * normalized_frequency;
    let coefficient = 2.0 * omega.cos();
    let mut previous = 0.0_f64;
    let mut previous2 = 0.0_f64;

    for sample in samples {
        let current = sample + coefficient * previous - previous2;
        previous2 = previous;
        previous = current;
    }

    let power = previous2 * previous2 + previous * previous - coefficient * previous * previous2;
    (power.max(0.0).sqrt() / samples.len() as f64).clamp(0.0, 1.0)
}

fn decode_pcm16(bytes: &[u8]) -> Vec<i16> {
    let mut samples = Vec::<i16>::with_capacity(bytes.len() / 2);
    for chunk in bytes.chunks_exact(2) {
        samples.push(i16::from_le_bytes([chunk[0], chunk[1]]));
    }
    samples
}

fn make_fingerprint(features: &AudioFeatures, voice_confidence: f64) -> String {
    format!(
        "r{:03}_p{:03}_z{:03}_d{:03}_l{:03}_s{:03}_h{:03}_v{:03}",
        quantize(features.rms, 1000.0),
        quantize(features.peak, 1000.0),
        quantize(features.zero_crossing_rate, 1000.0),
        quantize(features.dynamic_variation, 1000.0),
        quantize(features.low_band_energy + features.hum_band_energy, 1000.0),
        quantize(features.speech_band_energy, 1000.0),
        quantize(features.high_band_energy, 1000.0),
        quantize(voice_confidence, 1000.0),
    )
}

fn quantize(value: f64, scale: f64) -> i32 {
    (value.clamp(0.0, 1.0) * scale).round() as i32
}
