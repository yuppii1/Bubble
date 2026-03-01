# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |

## Reporting a Vulnerability

**DO NOT report security vulnerabilities via public GitHub issues.**

If you discover a security vulnerability within this project, please send an e-mail to the maintainers. All security vulnerabilities will be promptly addressed.

### A Note on API Keys
AITagger allows you to save API keys locally in `~/.aitagger_config.json`. Please ensure this file has restrictive permissions (`chmod 600`). AITagger handles this automatically on creation, but users should be aware that their keys are stored locally on their system.
