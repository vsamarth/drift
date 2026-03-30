//! Random two-word device labels (e.g. `Quiet River`) for defaults and UI.

use std::sync::OnceLock;

use rand::seq::SliceRandom;

/// First DNS label before `.`, trimmed (matches Flutter `DriftController` hostname handling).
/// Empty input yields a fresh random phrase.
pub fn normalize_hostname_label(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return random_device_name();
    }
    let first = trimmed.split('.').next().unwrap_or(trimmed).trim();
    if first.is_empty() {
        random_device_name()
    } else {
        first.to_owned()
    }
}

static PROCESS_DEFAULT_DEVICE_NAME: OnceLock<String> = OnceLock::new();

/// Display name for CLI: `DRIFT_DEVICE_NAME` / `HOSTNAME` / `COMPUTERNAME` (normalized), else one
/// random two-word name for the whole process (stable across send/receive/mDNS).
pub fn process_display_device_name() -> String {
    for key in ["DRIFT_DEVICE_NAME", "HOSTNAME", "COMPUTERNAME"] {
        if let Ok(value) = std::env::var(key) {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                return normalize_hostname_label(trimmed);
            }
        }
    }
    PROCESS_DEFAULT_DEVICE_NAME
        .get_or_init(random_device_name)
        .clone()
}

/// Picks one adjective and one noun, title-cased, separated by a space.
pub fn random_device_name() -> String {
    let mut rng = rand::thread_rng();
    let a = DEVICE_NAME_ADJECTIVES.choose(&mut rng).unwrap();
    let n = DEVICE_NAME_NOUNS.choose(&mut rng).unwrap();
    format!("{} {}", capitalize_word(a), capitalize_word(n))
}

fn capitalize_word(word: &str) -> String {
    let mut chars = word.chars();
    let Some(first) = chars.next() else {
        return String::new();
    };
    format!("{}{}", first.to_uppercase(), chars.as_str())
}

const DEVICE_NAME_ADJECTIVES: &[&str] = &[
    "amber", "brisk", "calm", "clear", "cozy", "crisp", "gentle", "golden", "humble", "jade",
    "kind", "lilac", "mellow", "misty", "nimble", "olive", "patient", "quiet", "rapid", "rusty",
    "silent", "silver", "simple", "steady", "swift", "tidy", "vivid", "woven",
];

const DEVICE_NAME_NOUNS: &[&str] = &[
    "badger", "beacon", "briar", "brook", "cedar", "compass", "coral", "creek", "curlew", "elm",
    "falcon", "fjord", "glen", "heron", "iris", "lark", "maple", "meadow", "mesa", "otter", "peak",
    "pine", "quail", "reef", "ridge", "river", "spruce", "starling", "thistle", "vale", "wren",
];

#[cfg(test)]
mod tests {
    use super::random_device_name;

    #[test]
    fn random_device_name_is_two_words() {
        let s = random_device_name();
        assert_eq!(s.split_whitespace().count(), 2);
        assert!(s.chars().next().unwrap().is_uppercase());
    }

    #[test]
    fn normalize_hostname_label_takes_first_label() {
        assert_eq!(super::normalize_hostname_label("my-mac.local."), "my-mac");
        assert_eq!(super::normalize_hostname_label("  lone  "), "lone");
    }
}
