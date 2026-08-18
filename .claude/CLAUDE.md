# AGENTS.md — Project Configuration for Autonomous Agents

> **Version**: v2.0
> **Date**: 2026-04-06
> **Template**: Copy this file to your repository root and fill in the CUSTOMIZE sections.

> **Agent Tool Compatibility**: This project uses the Agentic Engineering Framework and is compatible with [OpenCode](https://github.com/opencode-ai/opencode), [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code), [pi-mono](https://github.com/badlogic/pi-mono), and [Agent Zero](https://github.com/frdel/agent-zero). See `adapters/` for tool-specific setup.
>
> **Framework Docs**: https://github.com/Superlogic/AgenticEngineeringFramework

---

## Project Overview

**Name**: <!-- DETECTED:name -->ERCs<!-- /DETECTED -->
**Purpose**: <!-- DETECTED:description -->One or two sentences describing what this project does and who it serves.<!-- /DETECTED -->
**Primary Language**: <!-- DETECTED:language -->Ruby<!-- /DETECTED -->
**Framework**: <!-- DETECTED:framework -->e.g., FastAPI, Next.js, Gin, Actix-web<!-- /DETECTED -->
**Repository Type**: Single project / Monorepo

---

## Navigation

| Path | Type | Purpose | Entry Point |
|------|------|---------|-------------|
| `src/` | service | Main application | `src/app/main.py` |
| `src/auth/` | module | Authentication | `src/auth/router.py` |
| `tests/` | tests | Test suites | `tests/conftest.py` |

---

## Architecture

<!-- CUSTOMIZE: Describe your project's architecture in 3-10 bullet points -->

- **Service type**: e.g., REST API, web application, CLI tool, library, microservice
- **Database**: e.g., PostgreSQL via SQLAlchemy, MongoDB via Mongoose, none
- **External integrations**: e.g., Stripe payments, AWS S3, SendGrid email
- **Authentication**: e.g., JWT tokens, OAuth2 via Auth0, session-based, none
- **Deployment target**: e.g., AWS ECS, Kubernetes, Vercel, Heroku, bare metal

### Key Directories

<!-- CUSTOMIZE: List your actual directory structure and what each directory contains. When manifest.yml exists, this section is auto-populated from it. -->

| Directory | Purpose |
|---|---|
| `src/` | Application source code |
| `tests/` | Test suites (unit, integration) |
| `docs/` | Project documentation |
| `scripts/` | Build and deployment scripts |
| `migrations/` | Database migration files |

---

## Development Commands

<!-- CUSTOMIZE: Replace ALL placeholder commands with your actual commands -->

### Setup

```bash
# Install dependencies
YOUR_INSTALL_COMMAND    # e.g., pip install -r requirements.txt, npm install, cargo build

# Set up environment
cp .env.example .env    # Adjust if your project uses a different env setup
```

### Validation

```bash
# Run tests
<!-- DETECTED:test_command -->bundle exec rspec<!-- /DETECTED -->       # e.g., pytest, npm test, cargo test, go test ./...

# Run linter
<!-- DETECTED:lint_command -->rubocop<!-- /DETECTED -->       # e.g., ruff check ., eslint ., cargo clippy

# Run formatter check
<!-- DETECTED:format_command -->rubocop --auto-correct<!-- /DETECTED -->     # e.g., ruff format --check ., prettier --check ., cargo fmt --check

# Run type checker (if applicable)
<!-- DETECTED:typecheck_command -->YOUR_TYPECHECK_COMMAND<!-- /DETECTED -->  # e.g., mypy src/, tsc --noEmit, (not applicable for Go/Rust)

# Run build
YOUR_BUILD_COMMAND      # e.g., python -m build, npm run build, cargo build, go build ./...
```

### Run Locally

```bash
# Start development server
YOUR_DEV_COMMAND        # e.g., uvicorn main:app --reload, npm run dev, cargo run
```

---

## Coding Rules

<!-- CUSTOMIZE: Replace with your project's actual coding standards -->

### Style

- Follow the project's existing code style as enforced by the linter
- Use descriptive variable and function names
- Keep functions focused — one responsibility per function
- Maximum function length: ~50 lines (prefer shorter)

### Patterns

- Error handling: describe your project's error handling pattern
- Logging: describe your logging convention (e.g., structured JSON, Python logging module)
- Testing: describe expected test patterns (e.g., arrange-act-assert, given-when-then)
- Naming: describe naming conventions (e.g., snake_case for Python, camelCase for JS)

### Do NOT

- Do not use `print()` for logging — use the project's logging framework
- Do not add dependencies without documenting them
- Do not modify generated files (migrations, lock files) by hand
- Do not commit credentials, API keys, or secrets

---

## Risk Areas

<!-- CUSTOMIZE: Identify the sensitive parts of YOUR codebase -->

| Path / Area | Risk Level | Notes |
|---|---|---|
| `src/auth/` | High | Authentication and authorization — security critical |
| `src/payments/` | High | Financial calculations — requires human review |
| `migrations/` | High | Database schema changes — irreversible in production |
| `src/api/` | Medium | Public API surface — changes affect consumers |
| `tests/` | Low | Test-only changes — no production impact |
| `docs/` | Low | Documentation only |

---

## Review Expectations

<!-- CUSTOMIZE: Define what reviewers should check for in YOUR project -->

### All Changes

- [ ] Tests pass (existing + new)
- [ ] Linter passes with no new warnings
- [ ] No unrelated changes included
- [ ] Commit messages follow conventional format: `type(scope): description`

### Feature Changes

- [ ] Acceptance criteria met
- [ ] Edge cases handled
- [ ] Error messages are user-friendly
- [ ] Documentation updated if behavior changed

### Database Changes

- [ ] Migration is reversible
- [ ] No data loss in migration
- [ ] Indexes added for new query patterns
- [ ] DBA review requested

---

## Escalation

<!-- CUSTOMIZE: Define how and when agents should escalate to humans -->

### Channels

- **Standard**: Open a GitHub issue or comment on the PR
- **Urgent**: Tag @YOUR_TEAM_HANDLE in the PR

### Escalation Triggers

- Any change to authentication, authorization, or payment code
- Database migrations affecting production data
- Changes requiring coordination with external teams
- Ambiguous requirements after one clarification attempt
- Test failures that cannot be resolved in 2 attempts

---

## Environment Variables

<!-- CUSTOMIZE: List the env vars your project needs (never include actual values) -->

| Variable | Purpose | Required |
|---|---|---|
| `DATABASE_URL` | Database connection string | Yes |
| `API_KEY` | External API authentication | Yes |
| `LOG_LEVEL` | Logging verbosity (debug/info/warn/error) | No (default: info) |
| `PORT` | Server port | No (default: 8000) |

---

## Additional Context

<!-- CUSTOMIZE: Add any project-specific context an agent needs -->

### Known Issues

- Describe any known bugs or tech debt the agent should be aware of

### Recent Changes

- Note any recent architectural changes that might not be obvious from the code

### Team Conventions

- Any unwritten rules or preferences specific to your team

---

*This file follows the [Agentic Engineering Workflow Framework](https://github.com/Superlogic/AgenticEngineeringFramework) v2.0 standard.*
