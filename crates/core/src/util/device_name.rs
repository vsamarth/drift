//! Random two-word device labels (e.g. `Quiet River`) for defaults and UI.

use rand::seq::SliceRandom;

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
}
