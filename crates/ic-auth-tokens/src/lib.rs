#![deny(rust_2018_idioms)]

use crc::{Crc, CRC_32_ISO_HDLC};
use derive_more::Display;
use ic_cdk::api::call::call;
use ic_cdk::api::trap;
use ic_cdk::export::candid::{CandidType, Deserialize};
use ic_cdk::export::Principal;
use rand::distributions::{Alphanumeric, DistString};
use rand::{CryptoRng, RngCore, SeedableRng};
use serde::Serialize;
use std::convert::TryInto;

const DEFAULT_AUTH_TOKEN_CHAR_LENGTH: u8 = 255;
const PREFIX_SEPARATOR: &str = "_";
const CHECKSUM_CHAR_LENGTH: u8 = 6;
const DEFAULT_CRC_32: Crc<u32> = Crc::<u32>::new(&CRC_32_ISO_HDLC);

#[derive(CandidType, Debug, Deserialize, Display, Eq, PartialEq, Serialize)]
pub struct Prefix(pub String);

#[derive(CandidType, Debug, Deserialize, Display, Eq, PartialEq, Serialize)]
pub struct AuthToken(pub String);

pub fn make_auth_token<T: RngCore + CryptoRng>(rng: &mut T, prefix: &Prefix) -> AuthToken {
    make_auth_token_with_length(rng, prefix, DEFAULT_AUTH_TOKEN_CHAR_LENGTH)
}

pub fn make_auth_token_with_length<T: RngCore + CryptoRng>(
    rng: &mut T,
    prefix: &Prefix,
    length: u8,
) -> AuthToken {
    let sample_length: usize =
        length as usize - prefix.0.len() - PREFIX_SEPARATOR.len() - CHECKSUM_CHAR_LENGTH as usize;
    let sample: String = Alphanumeric.sample_string(rng, sample_length);
    make_auth_token_with_value(prefix, &sample)
}

fn make_auth_token_with_value(prefix: &Prefix, value: &str) -> AuthToken {
    let checksum = make_checksum(value);
    let base_62_encoded_checksum = base62_encode_checksum(&checksum);
    AuthToken(format!(
        "{}_{}{}",
        prefix.0, value, base_62_encoded_checksum.0
    ))
}

#[derive(CandidType, Debug, Deserialize, Display, Eq, PartialEq, Serialize)]
pub struct Checksum(pub u32);

pub fn make_checksum(input: &str) -> Checksum {
    make_checksum_with_crc(input, DEFAULT_CRC_32)
}

pub fn make_checksum_with_crc(input: &str, crc: Crc<u32>) -> Checksum {
    let mut digest = crc.digest();
    digest.update(input.as_bytes());
    Checksum(digest.finalize())
}

#[derive(CandidType, Debug, Deserialize, Display, Eq, PartialEq, Serialize)]
pub struct Base62EncodedChecksum(pub String);

pub fn base62_encode_checksum(checksum: &Checksum) -> Base62EncodedChecksum {
    let base62_encoded = base62::encode(checksum.0);
    let padded = format!(
        "{:0>width$}",
        base62_encoded,
        width = CHECKSUM_CHAR_LENGTH as usize
    );
    Base62EncodedChecksum(padded)
}

// Get a random number generator based on 'raw_rand'.
// Based on https://github.com/dfinity/internet-identity/blob/f76e36cc45e064b5e04b977de43698c13e7b55d9/src/internet_identity/src/main.rs#L683-L697
pub async fn make_rng<T: SeedableRng + CryptoRng>() -> T
where
    // raw_rand returns 32 bytes
    T: SeedableRng<Seed = [u8; 32]>,
{
    let raw_rand: Vec<u8> = match call(Principal::management_canister(), "raw_rand", ()).await {
        Ok((res,)) => res,
        Err((_, err)) => trap(&format!("failed to get seed: {}", err)),
    };

    let seed: <T as SeedableRng>::Seed = raw_rand[..].try_into().unwrap_or_else(|_| {
        trap(&format!(
            "when creating seed from raw_rand output, expected raw randomness to be of length 32, got {}",
            raw_rand.len()
        ));
    });

    T::from_seed(seed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand_chacha::ChaCha20Rng;

    #[test]
    fn test_make_base62_encoded_checksum() {
        let checksum = make_checksum("yzBdc2BoUJhBY13n2nv8k5FXq9fYC0");
        assert_eq!(base62_encode_checksum(&checksum).0, "0R8GcS");
    }

    #[test]
    fn test_make_auth_token_with_value() {
        let prefix = &Prefix("abc".to_string());
        let auth_token = make_auth_token_with_value(prefix, "yzBdc2BoUJhBY13n2nv8k5FXq9fYC0");
        assert_eq!(auth_token.0, "abc_yzBdc2BoUJhBY13n2nv8k5FXq9fYC00R8GcS");
    }

    const SEED: [u8; 32] = [0u8; 32];

    #[test]
    fn test_auth_token_length_default_prefix_a() {
        let mut rng = ChaCha20Rng::from_seed(SEED);
        let prefix = &Prefix("a".to_string());
        assert_eq!(
            make_auth_token(&mut rng, prefix).0.len(),
            DEFAULT_AUTH_TOKEN_CHAR_LENGTH as usize
        );
    }

    #[test]
    fn test_auth_token_length_default_prefix_ab() {
        let mut rng = ChaCha20Rng::from_seed(SEED);
        let prefix = &Prefix("ab".to_string());
        assert_eq!(
            make_auth_token(&mut rng, prefix).0.len(),
            DEFAULT_AUTH_TOKEN_CHAR_LENGTH as usize
        );
    }

    #[test]
    fn test_auth_token_length_default_prefix_abc() {
        let mut rng = ChaCha20Rng::from_seed(SEED);
        let prefix = &Prefix("abc".to_string());
        assert_eq!(
            make_auth_token(&mut rng, prefix).0.len(),
            DEFAULT_AUTH_TOKEN_CHAR_LENGTH as usize
        );
    }

    #[test]
    fn test_auth_token_length_40_prefix_a() {
        let length = 40;
        let mut rng = ChaCha20Rng::from_seed(SEED);
        let prefix = &Prefix("a".to_string());
        assert_eq!(
            make_auth_token_with_length(&mut rng, prefix, length)
                .0
                .len(),
            length as usize
        );
    }

    #[test]
    fn test_auth_token_length_40_prefix_ab() {
        let length = 40;
        let mut rng = ChaCha20Rng::from_seed(SEED);
        let prefix = &Prefix("ab".to_string());
        assert_eq!(
            make_auth_token_with_length(&mut rng, prefix, length)
                .0
                .len(),
            length as usize
        );
    }

    #[test]
    fn test_auth_token_length_40_prefix_abc() {
        let length = 40;
        let mut rng = ChaCha20Rng::from_seed(SEED);
        let prefix = &Prefix("abc".to_string());
        assert_eq!(
            make_auth_token_with_length(&mut rng, prefix, length)
                .0
                .len(),
            length as usize
        );
    }
}
