use rand::{rngs::OsRng, seq::SliceRandom, Rng};

use crate::VaultError;

const LOWER_UNAMBIGUOUS: &[u8] = b"abcdefghijkmnopqrstuvwxyz"; // no 'l'
const UPPER_UNAMBIGUOUS: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ"; // no 'I', 'O'
const DIGITS_UNAMBIGUOUS: &[u8] = b"23456789"; // no 0/1
const LOWER_ALL: &[u8] = b"abcdefghijklmnopqrstuvwxyz";
const UPPER_ALL: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DIGITS_ALL: &[u8] = b"0123456789";
const SYMBOLS: &[u8] = b"!@#$%^&*()-_=+[]{};:,.?";

const COMMON_BREACHED_PASSWORDS: &[&str] = &[
    "123456",
    "12345678",
    "123456789",
    "1234567890",
    "12345",
    "111111",
    "000000",
    "password",
    "password1",
    "password123",
    "passw0rd",
    "p@ssw0rd",
    "qwerty",
    "qwerty123",
    "abc123",
    "admin",
    "admin123",
    "root",
    "toor",
    "letmein",
    "welcome",
    "monkey",
    "dragon",
    "master",
    "sunshine",
    "iloveyou",
    "trustno1",
    "shadow",
    "baseball",
    "football",
    "changeme",
    "secret",
    "test",
    "guest",
];

#[derive(Debug, Clone)]
pub struct PasswordPolicy {
    pub length: usize,
    pub lower: bool,
    pub upper: bool,
    pub digits: bool,
    pub symbols: bool,
}

impl Default for PasswordPolicy {
    fn default() -> Self {
        Self {
            length: 24,
            lower: true,
            upper: true,
            digits: true,
            symbols: true,
        }
    }
}

/// Full Enpass-style password generation policy supporting pronounceable mode,
/// minimum vs. exact character-class counts, custom include/exclude characters,
/// and ambiguous character toggling.
#[derive(Debug, Clone)]
pub struct AdvancedPasswordPolicy {
    pub length: usize,
    pub pronounceable: bool,
    pub separator: String,
    pub lower: bool,
    pub upper: bool,
    pub digits: bool,
    pub symbols: bool,
    pub allow_ambiguous: bool,
    /// When `false`, `min_*` act as minimum counts (`Minimum` mode).
    /// When `true`, `min_*` act as exact counts (`Exactly` mode).
    pub exact_mode: bool,
    pub min_upper: usize,
    pub min_digits: usize,
    pub min_symbols: usize,
    pub exclude_chars: String,
    pub include_chars: String,
}

impl Default for AdvancedPasswordPolicy {
    fn default() -> Self {
        Self {
            length: 32,
            pronounceable: false,
            separator: "-".to_owned(),
            lower: true,
            upper: true,
            digits: true,
            symbols: true,
            allow_ambiguous: true,
            exact_mode: false,
            min_upper: 1,
            min_digits: 1,
            min_symbols: 1,
            exclude_chars: String::new(),
            include_chars: String::new(),
        }
    }
}

/// Generate a password using the OS CSPRNG, guaranteeing at least one
/// character from every enabled class.
pub fn generate_password(policy: &PasswordPolicy) -> Result<String, VaultError> {
    let classes: Vec<&[u8]> = [
        (policy.lower, LOWER_UNAMBIGUOUS),
        (policy.upper, UPPER_UNAMBIGUOUS),
        (policy.digits, DIGITS_UNAMBIGUOUS),
        (policy.symbols, SYMBOLS),
    ]
    .into_iter()
    .filter_map(|(on, set)| on.then_some(set))
    .collect();

    if classes.is_empty() {
        return Err(VaultError::Policy("enable at least one character class"));
    }
    if policy.length < classes.len() || policy.length > 256 {
        return Err(VaultError::Policy(
            "length must be between class count and 256",
        ));
    }

    let mut rng = OsRng;
    let pool: Vec<u8> = classes.iter().flat_map(|c| c.iter().copied()).collect();
    let mut out: Vec<u8> = classes
        .iter()
        .map(|c| c[rng.gen_range(0..c.len())])
        .collect();
    while out.len() < policy.length {
        out.push(pool[rng.gen_range(0..pool.len())]);
    }
    out.shuffle(&mut rng);
    Ok(String::from_utf8(out).expect("ascii only"))
}

/// Generate a password according to the full Enpass `AdvancedPasswordPolicy`.
pub fn generate_password_advanced(policy: &AdvancedPasswordPolicy) -> Result<String, VaultError> {
    if policy.length < 4 || policy.length > 256 {
        return Err(VaultError::Policy("length must be between 4 and 256"));
    }

    let filter_excluded = |bytes: &[u8]| -> Vec<u8> {
        bytes
            .iter()
            .copied()
            .filter(|&b| !policy.exclude_chars.as_bytes().contains(&b))
            .collect()
    };

    let lower_set = if policy.allow_ambiguous {
        filter_excluded(LOWER_ALL)
    } else {
        filter_excluded(LOWER_UNAMBIGUOUS)
    };
    let upper_set = if policy.allow_ambiguous {
        filter_excluded(UPPER_ALL)
    } else {
        filter_excluded(UPPER_UNAMBIGUOUS)
    };
    let digit_set = if policy.allow_ambiguous {
        filter_excluded(DIGITS_ALL)
    } else {
        filter_excluded(DIGITS_UNAMBIGUOUS)
    };
    let mut symbol_set = filter_excluded(SYMBOLS);
    for b in policy.include_chars.bytes() {
        if b.is_ascii_graphic()
            && !policy.exclude_chars.as_bytes().contains(&b)
            && !symbol_set.contains(&b)
            && !lower_set.contains(&b)
            && !upper_set.contains(&b)
            && !digit_set.contains(&b)
        {
            symbol_set.push(b);
        }
    }

    let mut rng = OsRng;

    if policy.pronounceable {
        return generate_pronounceable(
            policy,
            &lower_set,
            &upper_set,
            &digit_set,
            &symbol_set,
            &mut rng,
        );
    }

    let mut out: Vec<u8> = Vec::with_capacity(policy.length);
    let req_upper = if policy.upper {
        policy.min_upper.max(1)
    } else {
        0
    };
    let req_digits = if policy.digits {
        policy.min_digits.max(1)
    } else {
        0
    };
    let req_symbols = if policy.symbols {
        policy.min_symbols.max(1)
    } else {
        0
    };
    let req_lower = usize::from(policy.lower);

    if req_upper > 0 && upper_set.is_empty() {
        return Err(VaultError::Policy(
            "uppercase pool is empty after exclusions",
        ));
    }
    if req_digits > 0 && digit_set.is_empty() {
        return Err(VaultError::Policy("digits pool is empty after exclusions"));
    }
    if req_symbols > 0 && symbol_set.is_empty() {
        return Err(VaultError::Policy("symbols pool is empty after exclusions"));
    }
    if req_lower > 0 && lower_set.is_empty() {
        return Err(VaultError::Policy(
            "lowercase pool is empty after exclusions",
        ));
    }

    let total_required = req_upper + req_digits + req_symbols + req_lower;
    if total_required == 0 && policy.include_chars.is_empty() {
        return Err(VaultError::Policy("enable at least one character class"));
    }
    if total_required > policy.length {
        return Err(VaultError::Policy(
            "minimum/exact character counts exceed password length",
        ));
    }

    for _ in 0..req_upper {
        out.push(upper_set[rng.gen_range(0..upper_set.len())]);
    }
    for _ in 0..req_digits {
        out.push(digit_set[rng.gen_range(0..digit_set.len())]);
    }
    for _ in 0..req_symbols {
        out.push(symbol_set[rng.gen_range(0..symbol_set.len())]);
    }
    if req_lower > 0 && !policy.exact_mode {
        out.push(lower_set[rng.gen_range(0..lower_set.len())]);
    }

    let mut fill_pool: Vec<u8> = Vec::new();
    if policy.exact_mode {
        if policy.lower && !lower_set.is_empty() {
            fill_pool.extend_from_slice(&lower_set);
        }
        if fill_pool.is_empty() {
            // If lowercase was disabled in exact mode, allow remaining enabled sets to fill to length
            if policy.upper {
                fill_pool.extend_from_slice(&upper_set);
            }
            if policy.digits {
                fill_pool.extend_from_slice(&digit_set);
            }
            if policy.symbols {
                fill_pool.extend_from_slice(&symbol_set);
            }
        }
    } else {
        if policy.lower {
            fill_pool.extend_from_slice(&lower_set);
        }
        if policy.upper {
            fill_pool.extend_from_slice(&upper_set);
        }
        if policy.digits {
            fill_pool.extend_from_slice(&digit_set);
        }
        if policy.symbols {
            fill_pool.extend_from_slice(&symbol_set);
        }
    }

    for b in policy.include_chars.bytes() {
        if b.is_ascii_graphic() && !policy.exclude_chars.as_bytes().contains(&b) {
            fill_pool.push(b);
        }
    }

    if fill_pool.is_empty() && out.len() < policy.length {
        return Err(VaultError::Policy(
            "character pool is empty after exclusions",
        ));
    }

    while out.len() < policy.length {
        out.push(fill_pool[rng.gen_range(0..fill_pool.len())]);
    }

    out.shuffle(&mut rng);
    Ok(String::from_utf8(out).expect("ascii only"))
}

fn generate_pronounceable(
    policy: &AdvancedPasswordPolicy,
    lower_set: &[u8],
    upper_set: &[u8],
    digit_set: &[u8],
    symbol_set: &[u8],
    rng: &mut OsRng,
) -> Result<String, VaultError> {
    let vowels: Vec<u8> = b"aeiou"
        .iter()
        .copied()
        .filter(|b| lower_set.contains(b))
        .collect();
    let consonants: Vec<u8> = lower_set
        .iter()
        .copied()
        .filter(|b| !b"aeiou".contains(b))
        .collect();

    if vowels.is_empty() || consonants.is_empty() {
        return Err(VaultError::Policy(
            "pronounceable generator requires vowels and consonants",
        ));
    }

    let explicit_sep = policy
        .separator
        .as_bytes()
        .first()
        .copied()
        .filter(|b| b.is_ascii_graphic() || *b == b' ');

    let mut out: Vec<u8> = Vec::with_capacity(policy.length);
    let mut use_consonant = true;
    while out.len() < policy.length {
        if out.len() > 2 && out.len() + 2 < policy.length && out.len() % 5 == 4 {
            if let Some(sep_byte) = explicit_sep {
                out.push(sep_byte);
                use_consonant = true;
                continue;
            } else if policy.symbols && !symbol_set.is_empty() {
                out.push(symbol_set[rng.gen_range(0..symbol_set.len())]);
                use_consonant = true;
                continue;
            }
        }
        let ch = if use_consonant {
            consonants[rng.gen_range(0..consonants.len())]
        } else {
            vowels[rng.gen_range(0..vowels.len())]
        };
        out.push(ch);
        use_consonant = !use_consonant;
    }

    if policy.upper && !upper_set.is_empty() && !out.is_empty() {
        let up_char = out[0].to_ascii_uppercase();
        if upper_set.contains(&up_char) {
            out[0] = up_char;
        } else {
            out[0] = upper_set[rng.gen_range(0..upper_set.len())];
        }
    }
    if policy.digits && !digit_set.is_empty() && out.len() >= 2 {
        let last_idx = out.len() - 1;
        out[last_idx] = digit_set[rng.gen_range(0..digit_set.len())];
    }
    if explicit_sep.is_none()
        && policy.symbols
        && !symbol_set.is_empty()
        && out.len() >= 3
        && !out.iter().any(|b| symbol_set.contains(b))
    {
        let sym_idx = out.len() - 2;
        out[sym_idx] = symbol_set[rng.gen_range(0..symbol_set.len())];
    }

    Ok(String::from_utf8(out).expect("ascii only"))
}

/// Evaluates password strength (`0..=100` score, Enpass strength label, and compromised flag)
/// entirely in Rust without logging or exposing the password.
pub fn evaluate_password_strength(password: &str) -> (u8, &'static str, bool) {
    let trimmed = password.trim();
    if trimmed.is_empty() {
        return (0, "Weak", false);
    }

    let lower_pw = trimmed.to_ascii_lowercase();
    let base_alpha: String = lower_pw
        .trim_end_matches(|c: char| c.is_ascii_digit() || c.is_ascii_punctuation())
        .to_string();

    let is_compromised = COMMON_BREACHED_PASSWORDS.iter().any(|&bad| {
        lower_pw == bad || (!base_alpha.is_empty() && base_alpha == bad && trimmed.len() <= 10)
    });

    if is_compromised {
        return (15, "Weak", true);
    }

    let has_lower = trimmed.chars().any(|c| c.is_ascii_lowercase());
    let has_upper = trimmed.chars().any(|c| c.is_ascii_uppercase());
    let has_digit = trimmed.chars().any(|c| c.is_ascii_digit());
    let has_symbol = trimmed
        .chars()
        .any(|c| !c.is_ascii_alphanumeric() && !c.is_whitespace());

    let mut pool_size = 0usize;
    if has_lower {
        pool_size += 26;
    }
    if has_upper {
        pool_size += 26;
    }
    if has_digit {
        pool_size += 10;
    }
    if has_symbol {
        pool_size += 32;
    }
    if pool_size == 0 {
        pool_size = 26;
    }

    let mut unique_chars: Vec<char> = trimmed.chars().collect();
    unique_chars.sort_unstable();
    unique_chars.dedup();
    let unique_len = unique_chars.len();

    let class_count = [has_lower, has_upper, has_digit, has_symbol]
        .into_iter()
        .filter(|&x| x)
        .count();

    let len = trimmed.chars().count();
    let bits_per_char = (pool_size as f64).log2();
    let effective_len = (len as f64 * 0.7) + (unique_len as f64 * 0.3);
    let mut raw_score = (effective_len * bits_per_char * 1.1) as i32;

    if len < 8 {
        raw_score = raw_score.min(30);
    } else if len < 10 {
        raw_score = raw_score.min(48);
    } else if len < 12 && class_count < 3 {
        raw_score = raw_score.min(58);
    }

    if class_count >= 3 && len >= 14 {
        raw_score += 10;
    }
    if class_count == 4 && len >= 16 {
        raw_score += 8;
    }

    let score = raw_score.clamp(5, 100) as u8;
    let label = if score >= 80 {
        "Excellent"
    } else if score >= 60 {
        "Good"
    } else if score >= 40 {
        "Moderate"
    } else {
        "Weak"
    };

    (score, label, false)
}
