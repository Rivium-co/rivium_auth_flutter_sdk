## 0.2.0

- `getTokenResult({forceRefresh})`: the access token with its decoded fields, like Firebase's `getIdTokenResult()`.
  `claims` holds the custom claims your server set with `setCustomUserClaims` (for example `plan`, `role`), plus `sub`,
  `iat`, `exp`, `auth_time` and `amr`; also `expirationTime`, `issuedAtTime`, `authTime` and `signInProvider`. For
  showing things in the app; access is still decided on the server. Pass `forceRefresh: true` right after your server
  changed the claims.

## 0.1.1

- Sends `X-Rivium-SDK: auth-flutter/0.1.1` with every request so Rivium can show which SDK versions are in use. No behaviour change.

## 0.1.0

- Initial release.
- Sign-in methods: anonymous, Apple, Google, e-mail + password, magic link and Telegram code.
- Upgrade an anonymous user with `linkApple`, `linkGoogle` or `linkPassword`; the user keeps its id.
- Session kept in secure storage; the access token is renewed before it expires, with one request for all callers.
- `tokenProvider` and `chatTokenProvider` for the other Rivium SDKs.
- `RiviumAuthNonce` helper for Apple and Google sign-in; `rawNonce` is required for Apple and Google.
- Account deletion, sign out and sign out everywhere.
