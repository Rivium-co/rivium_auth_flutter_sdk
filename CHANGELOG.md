## 0.5.0

- `resendVerification(email:, password:)`: sends the confirmation link again to someone who can't sign in yet because
  your project requires a confirmed e-mail (signing in failed with `EMAIL_NOT_VERIFIED`). The e-mail and password the
  user typed prove the account; a wrong pair fails like signing in (`INVALID_CREDENTIALS`). It does not sign in.
  ```dart
  await auth.resendVerification(email: email, password: password);
  ```
- `continueUrl` on `signUpWithEmail`, `sendEmailVerification`, `resendVerification` and `sendPasswordReset`, like
  Firebase's continue URL: Rivium's confirm and reset pages show a "Continue" button that takes the user back to your
  app or site. It must be one of the project's redirect URLs.
- `sendEmailVerification`: `redirectUrl` is optional; without it the link opens Rivium's own confirm page.
- Sign-up of a project that requires a confirmed e-mail always sends the confirmation link, to Rivium's confirm page
  when you give no `redirectUrl`.
- Redirect URLs may include `http://localhost:<port>` and `http://127.0.0.1:<port>` for development.
- Ready-made sign-in screen: when the e-mail is not confirmed yet, it offers "Send again" and then shows "We sent a
  new link to …". New option `continueUrl`, used for sign-up, forgot password and "Send again".

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
