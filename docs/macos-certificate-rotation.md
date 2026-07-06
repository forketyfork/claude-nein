# Rotating the macOS Developer Certificate

This repository stores a macOS developer certificate in two GitHub Actions secrets:

- `MACOS_CERTIFICATE`: base64-encoded `.p12` archive
- `MACOS_CERTIFICATE_PWD`: password used when exporting that `.p12`

Neither CI workflow currently imports this certificate. [`.github/workflows/build.yml`](../.github/workflows/build.yml) runs `xcodebuild test` with code signing disabled (`CODE_SIGNING_ALLOWED=NO`), and [`.github/workflows/publish.yml`](../.github/workflows/publish.yml) builds `ClaudeNein-<version>-unsigned.zip` the same way. The secrets are kept for future signed-release automation (see `PLAN.md`); rotating them today has no effect on CI until a workflow imports the certificate again.

## Why CI Stopped Importing the Certificate

`build.yml` used to import this certificate with `Apple-Actions/import-codesign-certs` before running tests, because the project's `CODE_SIGN_STYLE = Automatic` setting otherwise needs a matching signing identity. That step failed for any pull request opened by Dependabot: GitHub does not pass repository Actions secrets to workflow runs triggered by `dependabot[bot]`, so `MACOS_CERTIFICATE` arrived empty and `Apple-Actions/import-codesign-certs` errored out immediately. Running tests never actually requires a real Apple signing identity, so `build.yml` now disables code signing outright instead of depending on secrets that Dependabot-triggered runs can't see.

## When to Rotate It

Rotate the certificate when:

- the Developer ID Application certificate has expired or is about to expire
- the private key was regenerated and the old `.p12` is no longer valid
- you are implementing signed release builds and need to seed the secrets with a current certificate

## What You Need

- a renewed `Developer ID Application` certificate in Keychain Access
- the private key for that certificate
- a freshly exported `.p12` file and its export password
- admin access to this repository's GitHub Actions secrets

If you already exported the renewed certificate from Keychain Access, start with the next section.

## Update the GitHub Secrets

1. Confirm the `.p12` contains the private key.

   In Keychain Access, the certificate should expand to show its private key underneath it. If the key is missing, GitHub Actions can import the file but Xcode signing will still fail.

2. Base64-encode the `.p12` as a single line.

   On macOS:

   ```bash
   base64 -i /path/to/DeveloperIDApplication.p12 | tr -d '\n' | pbcopy
   ```

   That copies the exact value expected by `MACOS_CERTIFICATE` to the clipboard. If you prefer to copy it manually:

   ```bash
   base64 -i /path/to/DeveloperIDApplication.p12 | tr -d '\n'
   ```

3. In GitHub, open this repository and go to `Settings -> Secrets and variables -> Actions`.

4. Replace `MACOS_CERTIFICATE` with the new base64 string.

5. Replace `MACOS_CERTIFICATE_PWD` with the password you used when exporting the new `.p12`.

6. Save both secrets.

Do not commit the `.p12` file, its password, or the base64 output to the repository.

## Using the Certificate in a Workflow Again

If a future workflow needs to import this certificate (for example, to produce signed and notarized release builds), re-add an `Apple-Actions/import-codesign-certs` step and point it at `secrets.MACOS_CERTIFICATE` / `secrets.MACOS_CERTIFICATE_PWD`. If that workflow should also run on Dependabot pull requests, remember that Dependabot-triggered runs don't receive these secrets unless they're duplicated into the separate "Dependabot secrets" store under `Settings -> Secrets and variables -> Dependabot`.

To confirm the identity locally on macOS before updating GitHub, inspect the certificate in your keychain:

```bash
security find-identity -v -p codesigning
```

You should see the renewed Developer ID identity listed there.

## Troubleshooting

### The import step fails immediately

Common causes:

- the base64 value in `MACOS_CERTIFICATE` was copied with line breaks or extra whitespace
- the `.p12` password in `MACOS_CERTIFICATE_PWD` does not match the exported file
- the `.p12` was exported without the private key
- the workflow run was triggered by `dependabot[bot]`, which never receives this secret

Re-export the certificate, re-encode it with `tr -d '\n'`, and update both secrets together.

### CI builds pass, but release artifacts are still unsigned

That is expected today. [`.github/workflows/publish.yml`](../.github/workflows/publish.yml) explicitly disables code signing and publishes `ClaudeNein-<version>-unsigned.zip`.

### The certificate was rotated, but there is still no signed release flow

Also expected. This repository's release automation still tracks code signing and notarization as future work in `PLAN.md`.
