use rand::{rngs::OsRng, seq::SliceRandom, Rng};

use crate::VaultError;

const LOWER: &[u8] = b"abcdefghijkmnopqrstuvwxyz"; // no 'l'
const UPPER: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ"; // no 'I', 'O'
const DIGITS: &[u8] = b"23456789"; // no 0/1
const SYMBOLS: &[u8] = b"!@#$%^&*()-_=+[]{};:,.?";

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

/// Generate a password using the OS CSPRNG, guaranteeing at least one
/// character from every enabled class.
pub fn generate_password(policy: &PasswordPolicy) -> Result<String, VaultError> {
    let classes: Vec<&[u8]> = [
        (policy.lower, LOWER),
        (policy.upper, UPPER),
        (policy.digits, DIGITS),
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
