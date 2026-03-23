# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and the project follows Semantic Versioning.

## [Unreleased]

### Added

- HTTP endpoint coverage for the local server
- file I/O edge case tests for corrupted JSONL and missing session directories
- contributor guide

### Changed

- server startup now uses Node's built-in `--env-file` support instead of custom `.env` parsing

## [1.0.0] - 2026-03-23

### Added

- initial public release of Limit Watch
- watchOS app for Codex and Claude usage viewing
- local server for Codex log parsing and Claude usage proxying
- basic server tests
