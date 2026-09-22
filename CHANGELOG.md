# Changelog

## 0.1.0 - 2026-09-22

Initial release.

- `Problem::Detailable` declares an exception class as an RFC 9457 problem, with a
  class-level `type` / `status` / `title` DSL and a per-occurrence `detail`.
- `Problem::Rescuable` renders those as `application/problem+json`, with overridable
  steps for building, reporting and rendering.
- `Problem::ExceptionsApp` answers exceptions that escape the controller.
- `Problem::I18nable` looks titles up through I18n.
- `Problem::RetryAfter` publishes a retry interval as a header and an extension member.
