# Contributing

Thanks for contributing to `Limit Watch`.

## Setup

Requirements:

- Node.js `20.6+`
- Xcode if you need to work on the watch app

Server setup:

```bash
cd server
cp .env.example .env
npm install
```

## Development

Useful commands:

```bash
cd server
npm run lint
npm test
npm start
```

The root [`README.md`](./README.md) is the main setup guide for running the full project.

## Pull Requests

- Keep changes focused
- Add or update tests when you change server behavior
- Do not commit local `.env` files, build artifacts, or machine-specific Xcode files
- Update docs when setup or runtime behavior changes

## Versioning

This project uses semantic versioning.

- breaking changes -> major
- new backwards-compatible features -> minor
- fixes/docs/tests -> patch
