# Repository Guidelines

## Agent-Specific Instructions

- Treat this as a host-run Elixir library, not a Phoenix app or service.
- Use `mise exec -- ...` by default for project commands so Elixir/Erlang versions from `mise.toml` are active.
- Do not edit `lib/generated/*.ex` directly; update the generator or `priv/openapi/spec3.sdk.json`, then run `mise exec -- make generate`.
- Do not commit real Stripe keys. Use test values and env vars such as `STRIPE_SECRET_KEY`, `STRIPE_API_BASE_URL`, and `STRIPE_API_UPLOAD_URL`.
- Avoid changing synced common-config files (`.formatter.exs`, `.credo.exs`, `.github/workflows/*`) unless the sync source is intentionally being updated.

## Project Structure & Module Organization

Hand-written source lives in `lib/stripe/`, with entry point `lib/stripe.ex`. OpenAPI parsing and code generation live in `lib/openapi/` and `lib/mix/tasks/generate.ex`. Generated Stripe resources are under `lib/generated/`. Tests live in `test/stripe/`, grouped by Stripe domain (`connect`, `subscriptions`, `payment_methods`, etc.). Helpers are in `test/support/`; fixtures are in `test/fixtures/`.

## Build, Test, and Development Commands

- `mise exec -- mix deps.get` fetches Elixir dependencies from `mix.lock`.
- `mise exec -- mix compile --warnings-as-errors` matches CI compile strictness.
- `mise exec -- mix test` runs ExUnit; by default `test/test_helper.exs` starts `stripe-mock`.
- `SKIP_STRIPE_MOCK_RUN=1 mise exec -- mix test` uses an already-running `stripe-mock`.
- `mise exec -- mix format` formats source; `mise exec -- mix format --check-formatted` matches CI.
- `mise exec -- mix credo --strict` runs the configured Credo checks.
- `mise exec -- mix dialyzer --format github` runs Dialyzer.
- `mise exec -- make generate` runs `mix stripe.generate` and formats generated output.
- `mise exec -- make download-openapi-current` downloads the OpenAPI spec from `.latest-tag-stripe-openapi-sdk`.

## Coding Style & Naming Conventions

Use standard Elixir formatting with `.formatter.exs`: 120-column line length, `plug` formatter imports, and generated files excluded. Module names follow `Stripe.*`; file names use snake_case. Prefer pipelines and explicit pattern matching where they help. Fallible public APIs should return tagged tuples such as `{:ok, value}` and `{:error, %Stripe.Error{}}`.

## Testing Guidelines

Tests use ExUnit with `seed: 0` and `disabled: true` excluded. Add tests near the changed domain, for example `test/stripe/connect/account_test.exs` for `Stripe.Account` behavior. Integration tests depend on `stripe-mock` on ports `12111` and `12112`; install it or run `docker run --rm -it -p 12111-12112:12111-12112 stripe/stripe-mock:latest` and set `SKIP_STRIPE_MOCK_RUN=1`. Run focused tests with `mise exec -- mix test path/to/file_test.exs`, then the relevant suite.

## Commit & Pull Request Guidelines

Commits must follow Conventional Commits, enforced by `.commitlintrc.yml`: allowed types include `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and `revert`; headers must be 100 characters or less. Examples: `fix: use post-read_body conn in WebhookPlug error responses`, `feat: add response_as option for flexible Stripe response formatting`.

For pull requests, include a behavior summary, related issues, and testing performed. Generated-code PRs should state the OpenAPI spec version and include regenerated files plus formatting.
