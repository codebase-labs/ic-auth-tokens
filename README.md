# ic-auth-tokens

![](https://img.shields.io/badge/status%EF%B8%8F-dangerous-red)

Generate authentication tokens based on the randomness provided by the Internet Computer.

## Why you probably shouldn't use this

This project was an experiment in discovering if authentication tokens are viable on the Internet Computer.

It has proven that this approach is too insecure to be useful but will serve as evidence for why alternative methods are necessary.

The following may still be beneficial:
* For projects on the Internet Computer, `make_rng` provides a convenient way to make a random number generator from `raw_rand`.
* For projects outside of the Internet Computer, `generate_auth_token` may still be useful provided the warnings below are taken into account.

## Warnings

### Authentication tokens should be treated like passwords

The Internet Computer supports authentication via services like [Internet Identity](https://internetcomputer.org/docs/current/tokenomics/identity-auth/what-is-ic-identity/) and [NFID](https://nfid.one/). Such services eliminate the risks associated with storing and managing passwords by removing them altogether. Authentication tokens reintroduce these risks.

### Authentication tokens sent in the clear

On the Internet Computer, authentication tokens that are sent in the clear will be seen by boundary nodes and all the nodes in a subnet.

### Authentication tokens should not be stored in plain text

[OWASP's Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) recommends using Argon2id to securely store hashed passwords. An example is provided in this repository.

### Authentication tokens may warrant expiration

Without expiration, authentication tokens are valid until they are manually revoked. Allowing users to configure expiration ptions when generating authentication tokens can help mitigate the security implications if a token becomes compromised.

## Implementation Details

### Design

This is heavily inspired by ["Behind GitHub's new authentication token formats"](https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/) and allows for generating tokens in the same format.

### Random Number Generation

`make_rng` uses the pseudo-random bytes returned by [`raw_rand`](https://internetcomputer.org/docs/current/references/ic-interface-spec#ic-raw_rand) to seed a cryptographically secure random number generator. Any RNG that implements the `SeedableRng` (where `Seed = [u8; 32]`) and `CryptoRng` traits is supported.

### Checksum

By generating a personal access token on GitHub and then Base62-decoding the checksum we can determine the CRC32 algorithm that was used to calculate it. This is the default algorithm used by `calculate_checksum`. `calculate_checksum_with_crc` can be used to calculate checksums using a different CRC32 algorithm.

### Token Length

["Behind GitHub's new authentication token formats"](https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/) links to another blog post entitled ["Authentication token format updates are generally available"](https://github.blog/changelog/2021-03-31-authentication-token-format-updates-are-generally-available/).

It says:

> The length of our tokens is remaining the same for now. However, GitHub tokens will likely increase in length in future updates, so integrators should plan to support tokens up to 255 characters after June 1, 2021.

Therefore, the default length used by `generate_auth_token` is 255 characters. `generate_auth_token_with_length` can be used to generate authentication tokens of a different length.
