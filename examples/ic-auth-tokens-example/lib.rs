#![deny(rust_2018_idioms)]

use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use ic_auth_tokens::{make_rng, AuthToken, Prefix};
use ic_cdk_macros::{query, update};
use rand_chacha::ChaCha20Rng;
use std::cell::RefCell;

#[derive(Default)]
struct State {
    auth_token_hash: Option<String>,
}

thread_local! {
    static STATE: RefCell<State> = RefCell::default();
}

#[update]
async fn generate_auth_token() -> AuthToken {
    let mut rng: ChaCha20Rng = make_rng().await;
    let prefix = Prefix("abc".to_string());
    let auth_token = ic_auth_tokens::generate_auth_token(&mut rng, &prefix);

    let salt = SaltString::generate(rng);
    let argon2 = Argon2::default();
    let auth_token_hash = argon2
        .hash_password(auth_token.0.as_bytes(), &salt)
        .unwrap()
        .to_string();

    STATE.with(|state_ref| {
        state_ref.borrow_mut().auth_token_hash = Some(auth_token_hash);
    });

    auth_token
}

#[query]
fn verify_auth_token(auth_token: AuthToken) -> Result<(), String> {
    STATE.with(|state_ref| {
        let state = state_ref.borrow();
        let auth_token_hash = state.auth_token_hash.as_ref().unwrap();
        let parsed_hash = PasswordHash::new(&auth_token_hash).map_err(|err| err.to_string())?;
        Argon2::default()
            .verify_password(auth_token.0.as_bytes(), &parsed_hash)
            .map_err(|err| err.to_string())
    })
}
