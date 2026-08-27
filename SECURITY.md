# Security Policy

## Credential handling

Never commit Firebase service-account JSON, private keys, OAuth bearer tokens, or FCM registration identifiers to source control. Prefer Application Default Credentials or a secret manager in deployed environments. The example file uses placeholders and must not be run with a credential file that is included in a package or mobile application.

The library is a server-side Dart client. It must not be embedded in a Flutter client application to hold Firebase administrative credentials.

## Reporting a vulnerability

Please report suspected credential exposure, authentication bypass, token-deletion bugs, or payload-injection issues privately through the repository’s security contact before opening a public issue. Include the affected version, a minimal reproduction, and whether credentials or production tokens may have been exposed. Do not include private keys or live bearer tokens in the report.
