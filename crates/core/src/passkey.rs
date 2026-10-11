//! Standards-compliant FIDO2 / WebAuthn Level 3 Passkey engine for Windows and Android.
//!
//! Aligns with <https://passkeys.dev/> specifications:
//! - Real ECDSA P-256 (`ES256`, COSE alg `-7`) PKCS#8 v1 PEM private keys (`KPEX_PASSKEY_PRIVATE_KEY_PEM`)
//!   interoperable with KeePassXC, Android 14+ `CredentialManager`, and Windows 11 `webauthn.dll`.
//! - Accurate `authenticatorData` flags (`UP`, strict `UV`, `BE=1` Backup Eligibility, `BS=1` Backup State, `AT`).
//! - Factory-minted WebAuthn challenge tokens (`PasskeyChallengeFactory`) with configuration-driven expiration.
//! - Related Origin Requests (ROR) validation enforcing the 5 unique eTLD-1 label limit.

use std::collections::BTreeSet;
use std::fmt;

use ring::{
    digest, hmac,
    rand::{SecureRandom, SystemRandom},
    signature::{
        EcdsaKeyPair, KeyPair, UnparsedPublicKey, ECDSA_P256_SHA256_ASN1,
        ECDSA_P256_SHA256_ASN1_SIGNING,
    },
};
use zeroize::Zeroizing;

use crate::VaultError;

/// COSE algorithm identifier for ES256 (ECDSA over P-256 with SHA-256).
pub const COSE_ALG_ES256: i32 = -7;

/// Maximum unique eTLD-1 labels permitted in Related Origin Requests (`/.well-known/webauthn`)
/// per WebAuthn Level 3 and `passkeys.dev/docs/advanced/related-origins/`.
pub const MAX_ROR_UNIQUE_LABELS: usize = 5;

/// Deterministic 16-byte AAGUID identifying VaultKeep's synced passkey provider
/// across Windows 11 (`webauthn.dll` plugin) and Android 14+ (`CredentialManager`).
pub const VAULTKEEP_AAGUID: [u8; 16] = [
    0x56, 0x4b, 0x50, 0x41, 0x53, 0x53, 0x4b, 0x45, 0x59, 0x50, 0x52, 0x4f, 0x56, 0x00, 0x01, 0x00,
];

/// WebAuthn `authenticatorData` flags byte bitmasks (`passkeys.dev` spec).
pub mod flags {
    /// Bit 0 (`0x01`): User Present (`UP`).
    pub const UP: u8 = 1 << 0;
    /// Bit 2 (`0x04`): User Verified (`UV`). Must ONLY be set if user verification actually occurred.
    pub const UV: u8 = 1 << 2;
    /// Bit 3 (`0x08`): Backup Eligibility (`BE`). `1` for multi-device / synced passkeys.
    pub const BE: u8 = 1 << 3;
    /// Bit 4 (`0x10`): Backup State (`BS`). `1` when backed up / synced (`BS` requires `BE == 1`).
    pub const BS: u8 = 1 << 4;
    /// Bit 6 (`0x40`): Attested Credential Data Present (`AT`). Set on `MakeCredential` (`create`).
    pub const AT: u8 = 1 << 6;
    /// Bit 7 (`0x80`): Extension Data Present (`ED`).
    pub const ED: u8 = 1 << 7;
}

/// Target OS platform for the passkey ceremony.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PasskeyPlatform {
    /// Windows 11 (`webauthn.dll` / browser / native plugin).
    Windows,
    /// Android 14+ (`androidx.credentials.CredentialProviderService` / Chrome / Custom Tabs).
    Android,
}

impl PasskeyPlatform {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Windows => "windows",
            Self::Android => "android",
        }
    }

    pub fn parse(input: &str) -> Result<Self, VaultError> {
        match input.trim().to_ascii_lowercase().as_str() {
            "windows" | "win" | "win32" | "win11" => Ok(Self::Windows),
            "android" => Ok(Self::Android),
            _ => Err(VaultError::Policy(
                "passkeys are currently enabled only for Windows and Android targets",
            )),
        }
    }
}

/// WebAuthn `UserVerificationRequirement` (`"required"`, `"preferred"`, `"discouraged"`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UserVerificationRequirement {
    Required,
    Preferred,
    Discouraged,
}

impl UserVerificationRequirement {
    pub fn parse(input: &str) -> Result<Self, VaultError> {
        match input.trim().to_ascii_lowercase().as_str() {
            "required" => Ok(Self::Required),
            "" | "preferred" => Ok(Self::Preferred),
            "discouraged" => Ok(Self::Discouraged),
            _ => Err(VaultError::Policy("invalid userVerification requirement")),
        }
    }
}

/// Resolves the `UV` bit according to `passkeys.dev/docs/reference/known-issues/`.
///
/// - Never sets `UV = true` unless `user_verified` is actually `true`.
/// - Fails closed when `UserVerificationRequirement::Required` is requested and `!user_verified`.
pub fn resolve_uv_flag(
    requirement: UserVerificationRequirement,
    user_verified: bool,
) -> Result<bool, VaultError> {
    if requirement == UserVerificationRequirement::Required && !user_verified {
        return Err(VaultError::Policy(
            "user verification is required for this passkey ceremony",
        ));
    }
    Ok(user_verified)
}

/// Scope of a factory-minted WebAuthn challenge token.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PasskeyCeremonyScope {
    Registration,
    Authentication,
}

impl PasskeyCeremonyScope {
    fn as_tag(self) -> &'static str {
        match self {
            Self::Registration => "webauthn.create",
            Self::Authentication => "webauthn.get",
        }
    }
}

/// Centralized configuration for factory-minted WebAuthn challenge tokens.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PasskeyTokenConfig {
    /// Expiration window in seconds for registration (`navigator.credentials.create`) challenges.
    pub registration_ttl_secs: u64,
    /// Expiration window in seconds for authentication (`navigator.credentials.get`) challenges.
    pub authentication_ttl_secs: u64,
}

impl PasskeyTokenConfig {
    pub const MIN_TTL_SECS: u64 = 15;
    pub const MAX_TTL_SECS: u64 = 600;
    pub const DEFAULT_REGISTRATION_TTL_SECS: u64 = 180;
    pub const DEFAULT_AUTHENTICATION_TTL_SECS: u64 = 120;

    pub fn validate(&self) -> Result<(), VaultError> {
        if !(Self::MIN_TTL_SECS..=Self::MAX_TTL_SECS).contains(&self.registration_ttl_secs)
            || !(Self::MIN_TTL_SECS..=Self::MAX_TTL_SECS).contains(&self.authentication_ttl_secs)
        {
            return Err(VaultError::Policy(
                "passkey challenge token TTL must be between 15 and 600 seconds",
            ));
        }
        Ok(())
    }
}

impl Default for PasskeyTokenConfig {
    fn default() -> Self {
        Self {
            registration_ttl_secs: Self::DEFAULT_REGISTRATION_TTL_SECS,
            authentication_ttl_secs: Self::DEFAULT_AUTHENTICATION_TTL_SECS,
        }
    }
}

/// Cryptographically sealed WebAuthn challenge token (`Tokenable`).
///
/// Cannot be constructed ad-hoc outside [`PasskeyChallengeFactory`].
#[derive(Clone, PartialEq, Eq)]
pub struct PasskeyChallengeToken {
    challenge_b64url: String,
    rp_id: String,
    scope: PasskeyCeremonyScope,
    issued_at_unix: i64,
    expiration_date_unix: i64,
    tag: [u8; 32],
}

impl PasskeyChallengeToken {
    pub fn challenge_b64url(&self) -> &str {
        &self.challenge_b64url
    }

    pub fn rp_id(&self) -> &str {
        &self.rp_id
    }

    pub fn scope(&self) -> PasskeyCeremonyScope {
        self.scope
    }

    pub fn issued_at_unix(&self) -> i64 {
        self.issued_at_unix
    }

    pub fn expiration_date_unix(&self) -> i64 {
        self.expiration_date_unix
    }
}

impl fmt::Debug for PasskeyChallengeToken {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PasskeyChallengeToken")
            .field("challenge_b64url", &self.challenge_b64url)
            .field("rp_id", &self.rp_id)
            .field("scope", &self.scope)
            .field("issued_at_unix", &self.issued_at_unix)
            .field("expiration_date_unix", &self.expiration_date_unix)
            .field("tag", &"[REDACTED]")
            .finish()
    }
}

/// Dedicated factory for minting and verifying time-limited WebAuthn ceremony challenge tokens.
pub struct PasskeyChallengeFactory {
    config: PasskeyTokenConfig,
    hmac_key: hmac::Key,
}

impl fmt::Debug for PasskeyChallengeFactory {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PasskeyChallengeFactory")
            .field("config", &self.config)
            .field("hmac_key", &"[REDACTED]")
            .finish()
    }
}

impl PasskeyChallengeFactory {
    /// Creates a new challenge factory with a fresh OS-random HMAC-SHA256 key and validated TTL config.
    pub fn new(config: PasskeyTokenConfig) -> Result<Self, VaultError> {
        config.validate()?;
        let rng = SystemRandom::new();
        let mut key_bytes = Zeroizing::new([0u8; 32]);
        rng.fill(&mut *key_bytes).map_err(|_| {
            VaultError::Policy("OS CSPRNG failure while initializing token factory")
        })?;
        let hmac_key = hmac::Key::new(hmac::HMAC_SHA256, &*key_bytes);
        Ok(Self { config, hmac_key })
    }

    /// Mints a sealed challenge token with a fresh 32-byte random challenge.
    pub fn mint_challenge(
        &self,
        rp_id: &str,
        scope: PasskeyCeremonyScope,
        now_unix: i64,
    ) -> Result<PasskeyChallengeToken, VaultError> {
        let rng = SystemRandom::new();
        let mut challenge = [0u8; 32];
        rng.fill(&mut challenge).map_err(|_| {
            VaultError::Policy("OS CSPRNG failure while minting WebAuthn challenge")
        })?;
        let challenge_b64url = encode_base64url(&challenge);
        self.mint_with_client_challenge(&challenge_b64url, rp_id, scope, now_unix)
    }

    /// Binds an RP-provided base64url challenge into a factory-minted, time-limited token.
    pub fn mint_with_client_challenge(
        &self,
        challenge_b64url: &str,
        rp_id: &str,
        scope: PasskeyCeremonyScope,
        now_unix: i64,
    ) -> Result<PasskeyChallengeToken, VaultError> {
        let cleaned_rp = normalize_rp_id(rp_id)?;
        let trimmed_challenge = challenge_b64url.trim();
        if trimmed_challenge.len() < 16 || !is_valid_base64url(trimmed_challenge) {
            return Err(VaultError::Policy(
                "WebAuthn challenge must be at least 16 base64url characters",
            ));
        }
        let ttl = match scope {
            PasskeyCeremonyScope::Registration => self.config.registration_ttl_secs as i64,
            PasskeyCeremonyScope::Authentication => self.config.authentication_ttl_secs as i64,
        };
        let expiration_date_unix = now_unix.saturating_add(ttl);
        let mac_input = Self::canonical_mac_input(
            trimmed_challenge,
            &cleaned_rp,
            scope,
            now_unix,
            expiration_date_unix,
        );
        let sig = hmac::sign(&self.hmac_key, &mac_input);
        let mut tag = [0u8; 32];
        tag.copy_from_slice(sig.as_ref());

        Ok(PasskeyChallengeToken {
            challenge_b64url: trimmed_challenge.to_owned(),
            rp_id: cleaned_rp,
            scope,
            issued_at_unix: now_unix,
            expiration_date_unix,
            tag,
        })
    }

    /// Validates a challenge token's HMAC tag, expiration date, ceremony scope, and RP ID binding.
    pub fn verify_challenge(
        &self,
        token: &PasskeyChallengeToken,
        expected_rp_id: &str,
        expected_scope: PasskeyCeremonyScope,
        now_unix: i64,
    ) -> Result<(), VaultError> {
        let cleaned_rp = normalize_rp_id(expected_rp_id)?;
        let mac_input = Self::canonical_mac_input(
            &token.challenge_b64url,
            &token.rp_id,
            token.scope,
            token.issued_at_unix,
            token.expiration_date_unix,
        );
        hmac::verify(&self.hmac_key, &mac_input, &token.tag)
            .map_err(|_| VaultError::Policy("invalid or tampered WebAuthn challenge token"))?;

        if token.scope != expected_scope {
            return Err(VaultError::Policy(
                "WebAuthn challenge token scope mismatch",
            ));
        }
        if token.rp_id != cleaned_rp {
            return Err(VaultError::Policy(
                "WebAuthn challenge token RP ID mismatch",
            ));
        }
        if now_unix >= token.expiration_date_unix {
            return Err(VaultError::Policy("WebAuthn challenge token has expired"));
        }
        Ok(())
    }

    fn canonical_mac_input(
        challenge_b64url: &str,
        rp_id: &str,
        scope: PasskeyCeremonyScope,
        issued_at_unix: i64,
        expiration_date_unix: i64,
    ) -> Vec<u8> {
        format!(
            "VK-PASSKEY-TOKEN-V1|{}|{}|{}|{}|{}",
            scope.as_tag(),
            rp_id,
            challenge_b64url,
            issued_at_unix,
            expiration_date_unix
        )
        .into_bytes()
    }
}

/// Output of a WebAuthn `MakeCredential` (registration) ceremony.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PasskeyRegistrationResponse {
    pub credential_id: String,
    pub rp_id: String,
    pub username: String,
    pub display_name: String,
    pub user_handle: String,
    pub platform: PasskeyPlatform,
    pub authenticator_attachment: String,
    pub transports: Vec<String>,
    pub authenticator_data_b64url: String,
    pub client_data_json_b64url: String,
    pub attestation_object_b64url: String,
    pub public_key_cose_b64url: String,
    pub flags: u8,
    pub user_verified: bool,
    pub backup_eligible: bool,
    pub backup_state: bool,
    pub sign_count: u32,
    pub cose_algorithm: i32,
    pub cred_props_rk: bool,
}

/// Output of a WebAuthn `GetAssertion` (authentication) ceremony.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PasskeyAssertionResponse {
    pub credential_id: String,
    pub rp_id: String,
    pub username: String,
    pub user_handle: String,
    pub platform: PasskeyPlatform,
    pub authenticator_attachment: String,
    pub authenticator_data_b64url: String,
    pub client_data_json_b64url: String,
    pub signature_b64url: String,
    pub flags: u8,
    pub user_verified: bool,
    pub backup_eligible: bool,
    pub backup_state: bool,
    pub sign_count: u32,
}

/// Generates a real NIST P-256 (`ES256`, COSE `-7`) keypair using OS CSPRNG, returning:
/// 1. Standard RFC 7468 PKCS#8 v1 PEM (`-----BEGIN PRIVATE KEY-----...`) in `Zeroizing<String>`, and
/// 2. The 65-byte SEC1 uncompressed public key (`0x04 || X || Y`).
pub fn generate_p256_pkcs8_pem() -> Result<(Zeroizing<String>, [u8; 65]), VaultError> {
    let rng = SystemRandom::new();
    let pkcs8_doc = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &rng)
        .map_err(|_| VaultError::Policy("failed to generate P-256 PKCS#8 passkey keypair"))?;
    let key_pair =
        EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, pkcs8_doc.as_ref(), &rng)
            .map_err(|_| VaultError::Policy("failed to validate generated P-256 PKCS#8 keypair"))?;

    let pub_bytes = key_pair.public_key().as_ref();
    if pub_bytes.len() != 65 || pub_bytes[0] != 0x04 {
        return Err(VaultError::Malformed(
            "unexpected SEC1 uncompressed public key length",
        ));
    }
    let mut uncompressed_pub = [0u8; 65];
    uncompressed_pub.copy_from_slice(pub_bytes);

    let b64 = Zeroizing::new(encode_base64_standard(pkcs8_doc.as_ref()));
    let mut pem = String::with_capacity(b64.len() + 64);
    pem.push_str("-----BEGIN PRIVATE KEY-----\n");
    for chunk in b64.as_bytes().chunks(64) {
        if let Ok(line) = std::str::from_utf8(chunk) {
            pem.push_str(line);
            pem.push('\n');
        }
    }
    pem.push_str("-----END PRIVATE KEY-----");
    Ok((Zeroizing::new(pem), uncompressed_pub))
}

/// Parses a PKCS#8 v1 PEM (`-----BEGIN PRIVATE KEY-----`) into a `ring::signature::EcdsaKeyPair`.
pub fn parse_p256_pkcs8_pem(pem: &str) -> Result<EcdsaKeyPair, VaultError> {
    let der = decode_pem_private_key(pem)?;
    let rng = SystemRandom::new();
    EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &der, &rng).map_err(|_| {
        VaultError::Malformed("invalid or unsupported PKCS#8 P-256 passkey private key")
    })
}

/// Extracts the 32-byte `(X, Y)` public key coordinates from a P-256 PKCS#8 PEM private key.
pub fn extract_p256_public_key_coords(pem: &str) -> Result<([u8; 32], [u8; 32]), VaultError> {
    let key_pair = parse_p256_pkcs8_pem(pem)?;
    let pub_bytes = key_pair.public_key().as_ref();
    if pub_bytes.len() != 65 || pub_bytes[0] != 0x04 {
        return Err(VaultError::Malformed(
            "invalid SEC1 P-256 public key encoding",
        ));
    }
    let mut x = [0u8; 32];
    let mut y = [0u8; 32];
    x.copy_from_slice(&pub_bytes[1..33]);
    y.copy_from_slice(&pub_bytes[33..65]);
    Ok((x, y))
}

/// Encodes a P-256 (`ES256`) public key into a canonical CTAP2/WebAuthn CBOR `COSE_Key` map (77 bytes).
///
/// Map structure (`0xa5`):
/// - `1` (`kty`): `2` (`EC2`)
/// - `3` (`alg`): `-7` (`ES256`)
/// - `-1` (`crv`): `1` (`P-256`)
/// - `-2` (`x`): 32-byte bstr
/// - `-3` (`y`): 32-byte bstr
pub fn encode_cose_p256_public_key(x: &[u8; 32], y: &[u8; 32]) -> Vec<u8> {
    let mut cbor = Vec::with_capacity(77);
    cbor.push(0xa5); // map(5)
                     // 1: 2 (kty: EC2)
    cbor.push(0x01);
    cbor.push(0x02);
    // 3: -7 (alg: ES256 -> negative int -1 - 6 = 0x26)
    cbor.push(0x03);
    cbor.push(0x26);
    // -1: 1 (crv: P-256 -> negative int -1 - 0 = 0x20)
    cbor.push(0x20);
    cbor.push(0x01);
    // -2: bytes(32) (x -> negative int -1 - 1 = 0x21)
    cbor.push(0x21);
    cbor.push(0x58);
    cbor.push(0x20);
    cbor.extend_from_slice(x);
    // -3: bytes(32) (y -> negative int -1 - 2 = 0x22)
    cbor.push(0x22);
    cbor.push(0x58);
    cbor.push(0x20);
    cbor.extend_from_slice(y);
    cbor
}

/// Encodes a WebAuthn `"none"` `attestationObject` in canonical CBOR:
/// `{"fmt": "none", "attStmt": {}, "authData": <bytes>}`.
pub fn encode_none_attestation_object(auth_data: &[u8]) -> Vec<u8> {
    let mut cbor = Vec::with_capacity(32 + auth_data.len());
    cbor.push(0xa3); // map(3)
                     // "fmt": "none"
    cbor.push(0x63);
    cbor.extend_from_slice(b"fmt");
    cbor.push(0x64);
    cbor.extend_from_slice(b"none");
    // "attStmt": {}
    cbor.push(0x67);
    cbor.extend_from_slice(b"attStmt");
    cbor.push(0xa0); // map(0)
                     // "authData": h'...'
    cbor.push(0x68);
    cbor.extend_from_slice(b"authData");
    if auth_data.len() < 24 {
        cbor.push(0x40 | (auth_data.len() as u8));
    } else if auth_data.len() <= u8::MAX as usize {
        cbor.push(0x58);
        cbor.push(auth_data.len() as u8);
    } else {
        let len = auth_data.len() as u16;
        cbor.push(0x59);
        cbor.extend_from_slice(&len.to_be_bytes());
    }
    cbor.extend_from_slice(auth_data);
    cbor
}

/// Builds WebAuthn `authenticatorData` bytes with `passkeys.dev` compliant flags.
///
/// Enforces that `BS` (Backup State) can never be set if `BE` (Backup Eligibility) is `false`.
pub fn build_authenticator_data(
    rp_id: &str,
    user_verified: bool,
    backup_eligible: bool,
    backup_state: bool,
    sign_count: u32,
    attested_credential: Option<(&[u8], &[u8])>,
) -> Result<(Vec<u8>, u8), VaultError> {
    if backup_state && !backup_eligible {
        return Err(VaultError::Policy(
            "invalid passkey flags: backup_state (BS) cannot be true when backup_eligible (BE) is false",
        ));
    }
    let rp_id_hash = digest::digest(&digest::SHA256, rp_id.as_bytes());
    let mut flag_byte = flags::UP;
    if user_verified {
        flag_byte |= flags::UV;
    }
    if backup_eligible {
        flag_byte |= flags::BE;
        if backup_state {
            flag_byte |= flags::BS;
        }
    }
    if attested_credential.is_some() {
        flag_byte |= flags::AT;
    }

    let mut auth_data = Vec::with_capacity(160);
    auth_data.extend_from_slice(rp_id_hash.as_ref()); // 32 bytes
    auth_data.push(flag_byte); // 1 byte
    auth_data.extend_from_slice(&sign_count.to_be_bytes()); // 4 bytes

    if let Some((cred_id_bytes, cose_public_key)) = attested_credential {
        if cred_id_bytes.is_empty() || cred_id_bytes.len() > 1023 {
            return Err(VaultError::Policy(
                "WebAuthn credential ID length must be between 1 and 1023 bytes",
            ));
        }
        auth_data.extend_from_slice(&VAULTKEEP_AAGUID); // 16 bytes
        let cred_len = cred_id_bytes.len() as u16;
        auth_data.extend_from_slice(&cred_len.to_be_bytes()); // 2 bytes
        auth_data.extend_from_slice(cred_id_bytes);
        auth_data.extend_from_slice(cose_public_key);
    }

    Ok((auth_data, flag_byte))
}

/// Builds WebAuthn `clientDataJSON` bytes for Windows (`https://...`) or Android (`android:apk-key-hash:...` / `https://...`).
pub fn build_client_data_json(
    ceremony_type: PasskeyCeremonyScope,
    challenge_b64url: &str,
    origin: &str,
    android_package_name: Option<&str>,
) -> Vec<u8> {
    let clean_origin = origin.trim();
    if let Some(pkg) = android_package_name
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        format!(
            r#"{{"type":"{}","challenge":"{}","origin":"{}","androidPackageName":"{}","crossOrigin":false}}"#,
            ceremony_type.as_tag(),
            challenge_b64url,
            clean_origin,
            pkg
        )
        .into_bytes()
    } else {
        format!(
            r#"{{"type":"{}","challenge":"{}","origin":"{}","crossOrigin":false}}"#,
            ceremony_type.as_tag(),
            challenge_b64url,
            clean_origin
        )
        .into_bytes()
    }
}

/// Signs `authenticatorData || SHA-256(clientDataJSON)` using the P-256 PKCS#8 PEM private key
/// and verifies the resulting ASN.1 DER signature against the keypair's public key before returning.
pub fn sign_webauthn_assertion(
    private_key_pem: &str,
    authenticator_data: &[u8],
    client_data_json: &[u8],
) -> Result<Vec<u8>, VaultError> {
    let key_pair = parse_p256_pkcs8_pem(private_key_pem)?;
    let client_data_hash = digest::digest(&digest::SHA256, client_data_json);

    let mut signed_payload = Vec::with_capacity(authenticator_data.len() + 32);
    signed_payload.extend_from_slice(authenticator_data);
    signed_payload.extend_from_slice(client_data_hash.as_ref());

    let rng = SystemRandom::new();
    let sig = key_pair
        .sign(&rng, &signed_payload)
        .map_err(|_| VaultError::Policy("failed to sign WebAuthn assertion payload"))?;

    // Self-verify signature before returning to guarantee keypair integrity.
    let peer_pub = UnparsedPublicKey::new(&ECDSA_P256_SHA256_ASN1, key_pair.public_key().as_ref());
    peer_pub
        .verify(&signed_payload, sig.as_ref())
        .map_err(|_| VaultError::Policy("WebAuthn assertion self-verification failed"))?;

    Ok(sig.as_ref().to_vec())
}

/// Verifies a WebAuthn assertion signature using the P-256 PKCS#8 PEM's public key.
pub fn verify_webauthn_assertion(
    private_key_pem: &str,
    authenticator_data: &[u8],
    client_data_json: &[u8],
    signature_der: &[u8],
) -> Result<(), VaultError> {
    let key_pair = parse_p256_pkcs8_pem(private_key_pem)?;
    let client_data_hash = digest::digest(&digest::SHA256, client_data_json);
    let mut signed_payload = Vec::with_capacity(authenticator_data.len() + 32);
    signed_payload.extend_from_slice(authenticator_data);
    signed_payload.extend_from_slice(client_data_hash.as_ref());

    let peer_pub = UnparsedPublicKey::new(&ECDSA_P256_SHA256_ASN1, key_pair.public_key().as_ref());
    peer_pub
        .verify(&signed_payload, signature_der)
        .map_err(|_| VaultError::Policy("WebAuthn assertion signature verification failed"))
}

/// Validates that `rp_id` is authorized for `origin`, supporting:
/// 1. Standard WebAuthn domain matching (`origin_host == rp_id` or registrable subdomain `*.rp_id`),
/// 2. Android APK key-hash origins (`android:apk-key-hash:...`) when verified via Digital Asset Links, and
/// 3. WebAuthn Level 3 **Related Origin Requests (ROR)** (`allowed_related_origins` from `/.well-known/webauthn`),
///    strictly enforcing the `passkeys.dev` maximum of **5 unique eTLD-1 labels** (`MAX_ROR_UNIQUE_LABELS`).
pub fn validate_rp_id_for_origin(
    rp_id: &str,
    origin: &str,
    allowed_related_origins: &[String],
) -> Result<(), VaultError> {
    let clean_rp = normalize_rp_id(rp_id)?;
    let trimmed_origin = origin.trim();
    if trimmed_origin.is_empty() {
        return Err(VaultError::Policy(
            "WebAuthn ceremony origin must not be empty",
        ));
    }

    // Android native CredentialManager origin (`android:apk-key-hash:<base64url-sha256>`)
    if let Some(hash_part) = trimmed_origin.strip_prefix("android:apk-key-hash:") {
        if hash_part.len() >= 32 && is_valid_base64url(hash_part) {
            return Ok(());
        }
        return Err(VaultError::Policy(
            "malformed Android APK key hash origin for passkey ceremony",
        ));
    }

    let origin_lower = trimmed_origin.to_ascii_lowercase();
    let is_https = origin_lower.starts_with("https://");
    let is_localhost_http = origin_lower.starts_with("http://localhost")
        || origin_lower.starts_with("http://127.0.0.1");
    if !is_https && !is_localhost_http {
        return Err(VaultError::Policy(
            "WebAuthn origin must use https:// (or http://localhost)",
        ));
    }

    let origin_host = extract_origin_host(&origin_lower)?;
    if origin_host == clean_rp || origin_host.ends_with(&format!(".{clean_rp}")) {
        return Ok(());
    }

    // Check Related Origin Requests (ROR) with the 5-unique-label rule (`passkeys.dev/docs/advanced/related-origins/`)
    if !allowed_related_origins.is_empty() {
        let mut unique_labels = BTreeSet::new();
        let mut matched = false;
        for ro in allowed_related_origins {
            let ro_lower = ro.trim().to_ascii_lowercase();
            if !ro_lower.starts_with("https://") {
                continue;
            }
            let ro_host = extract_origin_host(&ro_lower)?;
            let label = extract_etld_minus_one_label(&ro_host);
            unique_labels.insert(label);
            if unique_labels.len() > MAX_ROR_UNIQUE_LABELS {
                return Err(VaultError::Policy(
                    "Related Origin Requests exceed maximum of 5 unique eTLD-1 domain labels",
                ));
            }
            if ro_host == origin_host {
                matched = true;
            }
        }
        if matched {
            return Ok(());
        }
    }

    Err(VaultError::Policy(
        "origin is not authorized for the requested relying party ID",
    ))
}

fn extract_origin_host(origin_lower: &str) -> Result<String, VaultError> {
    let without_scheme = origin_lower
        .split_once("://")
        .map(|(_, rest)| rest)
        .unwrap_or(origin_lower);
    let authority = without_scheme
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default();
    let host = authority
        .split(':')
        .next()
        .unwrap_or_default()
        .trim_end_matches('.');
    if host.is_empty() {
        return Err(VaultError::Policy("origin is missing a valid host"));
    }
    Ok(host.to_owned())
}

/// Extracts the registrable eTLD-1 label (e.g. `"shopping"` for both `"shopping.com"` and `"shopping.co.uk"`)
/// as defined by `passkeys.dev/docs/advanced/related-origins/`.
fn extract_etld_minus_one_label(host: &str) -> String {
    const MULTI_PART_TLDS: &[&str] = &[
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.jp", "ne.jp",
        "or.jp", "co.in", "net.in", "org.in", "com.br", "co.nz", "co.za", "com.sg", "com.mx",
    ];
    let parts: Vec<&str> = host.split('.').filter(|s| !s.is_empty()).collect();
    if parts.len() <= 1 {
        return host.to_owned();
    }
    if parts.len() >= 3 {
        let last_two = format!("{}.{}", parts[parts.len() - 2], parts[parts.len() - 1]);
        if MULTI_PART_TLDS.contains(&last_two.as_str()) {
            return parts[parts.len() - 3].to_owned();
        }
    }
    parts[parts.len() - 2].to_owned()
}

pub fn normalize_rp_id(rp_id: &str) -> Result<String, VaultError> {
    let s = rp_id.trim().to_ascii_lowercase();
    let s = if let Some((_, rest)) = s.split_once("://") {
        rest
    } else {
        s.as_str()
    };
    let s = s.split(['/', '?', '#', ':']).next().unwrap_or(s);
    let s = s.strip_prefix("www.").unwrap_or(s).trim_end_matches('.');
    if s.is_empty()
        || !s
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.')
    {
        return Err(VaultError::Policy("invalid relying party ID"));
    }
    Ok(s.to_owned())
}

pub fn is_valid_base64url(input: &str) -> bool {
    !input.is_empty()
        && input
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

pub fn encode_base64url(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::with_capacity((bytes.len() * 4).div_ceil(3));
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(ALPHABET[((triple >> 18) & 0x3F) as usize] as char);
        out.push(ALPHABET[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 {
            out.push(ALPHABET[((triple >> 6) & 0x3F) as usize] as char);
        }
        if chunk.len() > 2 {
            out.push(ALPHABET[(triple & 0x3F) as usize] as char);
        }
    }
    out
}

pub fn decode_base64url(input: &str) -> Result<Vec<u8>, VaultError> {
    let trimmed = input.trim().trim_end_matches('=');
    let mut out = Vec::with_capacity(trimmed.len() * 3 / 4);
    let mut buf = 0u32;
    let mut bits = 0u8;
    for b in trimmed.bytes() {
        let val = match b {
            b'A'..=b'Z' => b - b'A',
            b'a'..=b'z' => b - b'a' + 26,
            b'0'..=b'9' => b - b'0' + 52,
            b'-' | b'+' => 62,
            b'_' | b'/' => 63,
            _ => return Err(VaultError::Malformed("invalid base64url character")),
        };
        buf = (buf << 6) | (val as u32);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xFF) as u8);
        }
    }
    Ok(out)
}

fn encode_base64_standard(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(ALPHABET[((triple >> 18) & 0x3F) as usize] as char);
        out.push(ALPHABET[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 {
            out.push(ALPHABET[((triple >> 6) & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(ALPHABET[(triple & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}

fn decode_pem_private_key(pem: &str) -> Result<Zeroizing<Vec<u8>>, VaultError> {
    let trimmed = pem.trim();
    let body = trimmed
        .strip_prefix("-----BEGIN PRIVATE KEY-----")
        .and_then(|s| s.strip_suffix("-----END PRIVATE KEY-----"))
        .ok_or(VaultError::Malformed(
            "passkey private key must be in PKCS#8 PEM format",
        ))?;

    let filtered: Zeroizing<String> =
        Zeroizing::new(body.chars().filter(|c| !c.is_whitespace()).collect());
    let decoded = decode_base64url(&filtered)?;
    Ok(Zeroizing::new(decoded))
}
