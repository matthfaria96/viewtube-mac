//! Parâmetro de tempo dos links do YouTube (`TimeParam.swift`):
//! `90`, `90s`, `1m30s`, `1h2m3s`, `1:30`, `1:02:03`.

/// Uma semana: nenhum vídeo real passa disso, e o limite barra "inf", "1e400" etc.
pub const MAXIMUM: f64 = 7.0 * 24.0 * 3600.0;

pub fn parse(raw: &str) -> Option<f64> {
    let value = parse_unchecked(raw)?;
    (value.is_finite() && value >= 0.0 && value <= MAXIMUM).then_some(value)
}

fn parse_unchecked(raw: &str) -> Option<f64> {
    let text = raw.trim_matches(|c: char| c == ' ' || c == '\t').to_lowercase();
    if text.is_empty() {
        return None;
    }
    if text.contains(':') {
        return parse_clock(&text);
    }
    let plain = if text.ends_with('s') && !text.contains(['h', 'm']) { &text[..text.len() - 1] } else { &text[..] };
    if let Some(seconds) = swift_double(plain) {
        return (seconds >= 0.0).then_some(seconds);
    }
    parse_units(&text)
}

fn parse_clock(text: &str) -> Option<f64> {
    let parts: Vec<Option<f64>> = text.split(':').map(swift_double).collect();
    if !(2..=3).contains(&parts.len()) || !parts.iter().all(|p| p.map_or(false, |v| v >= 0.0)) {
        return None;
    }
    Some(parts.into_iter().flatten().fold(0.0, |acc, v| acc * 60.0 + v))
}

fn parse_units(text: &str) -> Option<f64> {
    let mut total = 0.0;
    let mut number = String::new();
    for c in text.chars() {
        if c.is_numeric() || c == '.' {
            number.push(c);
        } else if let (Some(mult), Some(value)) = (multiplier(c), swift_double(&number)) {
            total += value * mult;
            number.clear();
        } else {
            return None;
        }
    }
    number.is_empty().then_some(total)
}

fn multiplier(c: char) -> Option<f64> {
    match c {
        'h' => Some(3600.0),
        'm' => Some(60.0),
        's' => Some(1.0),
        _ => None,
    }
}

/// `Double(String)` do Swift: aceita "inf", "nan", "1e400" (→ inf); recusa espaço e texto vazio.
pub(crate) fn swift_double(text: &str) -> Option<f64> {
    if text.is_empty() || text.chars().any(char::is_whitespace) {
        return None;
    }
    text.parse::<f64>().ok()
}
