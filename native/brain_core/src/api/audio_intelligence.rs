use flutter_rust_bridge::frb;

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

    let samples = decode_pcm16(bytes);
    if samples.len() < 16 {
        return None;
    }

    let mut sum_squares = 0.0_f64;
    let mut peak = 0.0_f64;
    let mut crossings = 0_i32;
    let mut previous = samples[0];
    let mut low_sum = 0.0_f64;
    let mut mid_sum = 0.0_f64;
    let mut high_sum = 0.0_f64;

    for (index, sample) in samples.iter().enumerate() {
        let value = *sample as f64 / 32768.0;
        let abs = value.abs();
        peak = peak.max(abs);
        sum_squares += value * value;
        if index > 0 && ((previous < 0 && *sample >= 0) || (previous >= 0 && *sample < 0)) {
            crossings += 1;
        }
        previous = *sample;

        let bucket = index % 3;
        if bucket == 0 {
            low_sum += abs;
        } else if bucket == 1 {
            mid_sum += abs;
        } else {
            high_sum += abs;
        }
    }

    let sample_count = samples.len() as f64;
    let rms = (sum_squares / sample_count).sqrt();
    let zero_crossing_rate = crossings as f64 / sample_count;
    let low = low_sum / sample_count;
    let mid = mid_sum / sample_count;
    let high = high_sum / sample_count;
    let dynamic_variation = ((mid - low).abs() + (high - mid).abs() + (high - low).abs()) / 3.0;
    let speech_band_energy = (mid * 1.45 + high * 0.55).min(1.0);
    let voice_confidence = ((speech_band_energy * 4.2) + (zero_crossing_rate * 1.7) + (rms * 1.4))
        .clamp(0.0, 1.0);

    let near_voice_likely = voice_confidence >= 0.62 && rms >= 0.022 && peak >= 0.12;
    let possible_far_voice_likely = !near_voice_likely
        && voice_confidence >= 0.46
        && rms >= 0.010
        && peak >= 0.045;
    let allowed_ambient_likely = !near_voice_likely
        && !possible_far_voice_likely
        && (rms < 0.018 || dynamic_variation < 0.009);
    let fingerprint = make_fingerprint(rms, peak, zero_crossing_rate, dynamic_variation, voice_confidence);
    let repeated_fingerprint = previous_fingerprint
        .map(|previous| !previous.is_empty() && previous == fingerprint)
        .unwrap_or(false);
    let label = if near_voice_likely {
        "near_voice"
    } else if possible_far_voice_likely {
        "far_or_background_voice"
    } else if allowed_ambient_likely {
        "allowed_ambient"
    } else {
        "unclear_audio"
    };

    Some(NativeAudioIntelligenceResult {
        ready: true,
        label: label.to_string(),
        rms,
        peak,
        zero_crossing_rate,
        dynamic_variation,
        voice_confidence,
        near_voice_likely,
        possible_far_voice_likely,
        allowed_ambient_likely,
        repeated_fingerprint,
        fingerprint,
    })
}

fn decode_pcm16(bytes: &[u8]) -> Vec<i16> {
    let mut samples = Vec::<i16>::with_capacity(bytes.len() / 2);
    for chunk in bytes.chunks_exact(2) {
        samples.push(i16::from_le_bytes([chunk[0], chunk[1]]));
    }
    samples
}

fn make_fingerprint(
    rms: f64,
    peak: f64,
    zero_crossing_rate: f64,
    dynamic_variation: f64,
    voice_confidence: f64,
) -> String {
    format!(
        "r{:03}_p{:03}_z{:03}_d{:03}_v{:03}",
        quantize(rms, 1000.0),
        quantize(peak, 1000.0),
        quantize(zero_crossing_rate, 1000.0),
        quantize(dynamic_variation, 1000.0),
        quantize(voice_confidence, 1000.0),
    )
}

fn quantize(value: f64, scale: f64) -> i32 {
    (value.clamp(0.0, 1.0) * scale).round() as i32
}
