# problem: RFC 9457 Problem Details for Rails APIs

`problem` renders the errors a Rails API raises as
[RFC 9457](https://www.rfc-editor.org/rfc/rfc9457.html) problem details. An error class
declares its type, title and status once, next to the code that raises it, and a
controller concern turns any of them into an `application/problem+json` response. A
companion exceptions app covers what Rails raises before your controller runs, so a
routing error and a business rule violation come back in the same shape.

```ruby
class Errors::Forbidden < Errors::ApiError
  type "forbidden"
  status 403
  title "Forbidden"
end

raise Errors::Forbidden.new(detail: "Only the owner can cancel this order")
```

```console
$ curl -i https://api.example.com/orders/1/cancel
HTTP/1.1 403 Forbidden
Content-Type: application/problem+json

{"type":"forbidden","title":"Forbidden","status":403,"detail":"Only the owner can cancel this order"}
```

## Features

- **One place per error.** Status, title and type live on the class, not in a mapping
  table that drifts away from the code raising it.
- **Stable identifiers for clients.** Callers dispatch on `type`, so you can reword a
  title without breaking them.
- **Covers what the controller never sees.** Routing errors, unreadable bodies and
  middleware failures render as problem documents too, carrying the status text rather
  than the exception message.
- **Localized titles**, keyed by type, with a one-line include.
- **Small.** Two mixins, an exceptions app and a renderer. Under 250 lines of code, and
  `actionpack` is the only dependency.
- **Typed.** RBS signatures ship with the gem.

## Requirements

Ruby 3.3 or later, and `actionpack` 7.0 or later. `Problem::I18nable` additionally needs
the `i18n` gem, which Rails already brings.

## Installation

```
bundle add problem
```

Rails wires itself up through a railtie. Add an initializer for the URI prefix your type
identifiers live under:

```ruby
# config/initializers/problem.rb
Rails.application.configure do
  config.problem.type_prefix = "https://api-probs.example.com/"
end
```

`config/application.rb` and the environment files work too.

Outside Rails, call `Problem.install!` at boot and configure it with
`Problem.configure { |c| c.type_prefix = "..." }`.

## Getting started

### 1. Give your errors a common base

```ruby
# app/models/errors.rb
module Errors
  class ApiError < StandardError
    include Problem::Detailable
  end

  class BadRequest < ApiError
    type "bad-request"
    status 400
    title "Bad Request"
  end

  class Unauthorized < ApiError
    type "unauthorized"
    status 401
    title "Unauthorized"
  end

  class Forbidden < ApiError
    type "forbidden"
    status 403
    title "Forbidden"
  end

  class NotFound < ApiError
    type "not-found"
    status 404
    title "Not Found"
  end
end
```

One base class carrying the concern is enough. Everything under it inherits the
declaration and overrides only what differs.

### 2. Rescue them once

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include Problem::Rescuable
end
```

### 3. Raise them

```ruby
raise Errors::NotFound unless @order

raise Errors::Forbidden.new(detail: "Only the owner can cancel this order")
```

`detail` is the part that differs between two occurrences of the same problem. Everything
else belongs to the class, so it is declared once.

## Defining your own errors

Inherit from the closest base and declare what changes:

```ruby
class Orders::AlreadyShipped < Errors::UnprocessableContent
  type "order-already-shipped"
  title "Order Already Shipped"
end
```

A subclass that declares nothing renders exactly as its parent:

```ruby
class Errors::ConfidentialClientRequired < Errors::Unauthorized; end
```

That is worth knowing deliberately. When a caller must not be able to tell two failures
apart, an empty subclass is the whole implementation.

## Localized titles

`title` is the only member written for a human, so it is the only one worth translating.
Include `Problem::I18nable` in your base class:

```ruby
module Errors
  class ApiError < StandardError
    include Problem::I18nable
  end
end
```

```yaml
# config/locales/en.yml
en:
  problem_details:
    titles:
      not_found: "Not Found"
      forbidden: "Forbidden"
```

Titles are keyed by the declared type with dashes replaced, under
`problem_details.titles`. Both are adjustable:

```ruby
class Errors::ApiError < StandardError
  include Problem::I18nable

  title_scope "errors.titles"      # inherited by subclasses
end

class Errors::NotFound < Errors::ApiError
  type "gone-missing"
  status 404
  title_key :not_found             # when the key should not follow the type
end
```

`Problem::I18nable` brings `Problem::Detailable` with it, so one include covers both. A
class that spells out a literal `title` keeps it, which lets a codebase move over
gradually.

Then establish the locale around rendering:

```ruby
class ApplicationController < ActionController::API
  include Problem::Rescuable

  private def around_problem_render(&) = I18n.with_locale(negotiated_locale, &)
end
```

That wrapper is not optional if you localize. Rails has already unwound your
`around_action` by the time an error renders, so the locale has to be re-established
here. [DESIGN.md](DESIGN.md#localization) explains why.

## Catching what escapes the controller

A routing error, an unreadable request body or a failure in middleware never reaches a
controller, so `Problem::Rescuable` never sees it. Wire up the exceptions app:

```ruby
# config/initializers/problem.rb
Rails.application.configure do
  config.exceptions_app = Problem::ExceptionsApp.new(
    ActionDispatch::PublicExceptions.new(Rails.public_path),
  )
end
```

Browsers keep getting the static error pages. Everything else gets a problem document,
with the status Rails already mapped the exception to.

## Error reporting

5xx problems are reported through `ActiveSupport.error_reporter`, which Sentry and similar
gems subscribe to. 4xx are not, on the grounds that an expected client error is not an
incident. Both are overridable:

```ruby
private def report_problem(error, _problem) = Sentry.capture_exception(error)

private def report_problem?(_error, problem) = problem.status >= 500
```

## Telling clients when to retry

```ruby
class Errors::TooManyRequests < Errors::ApiError
  include Problem::RetryAfter

  type "too-many-requests"
  status 429
  title "Try again in %{retry_after} seconds"
end

raise Errors::TooManyRequests.new(retry_after: 30)
```

Sends a `Retry-After` header, interpolates the wait into the title, and adds a
`retry_after` member to the body. A `Time` works in place of seconds.

## Extension members

RFC 9457 lets a problem carry extra top-level members. Return them from the occurrence:

```ruby
class Orders::PaymentDeclined < Errors::UnprocessableContent
  type "payment-declined"
  title "Payment Declined"

  def problem_extensions = {decline_code: "insufficient_funds"}
end
```

```json
{"type":"payment-declined","title":"Payment Declined","status":422,"decline_code":"insufficient_funds"}
```

To fill `instance`, which identifies the occurrence rather than the type, use the request:

```ruby
private def problem_for(error) = error.to_problem.with(instance: request.fullpath)
```

## Reference

Members of the rendered document:

| member | set by | notes |
|---|---|---|
| `type` | `type "slug"` | Resolved against `type_prefix`. Defaults to `about:blank`. |
| `title` | `title "..."`, or `Problem::I18nable` | Short, human readable, constant for the type. |
| `status` | `status 403` | Always matches the HTTP status. |
| `detail` | `new(detail:)` | Specific to the occurrence. Omitted when absent. |
| `instance` | `problem_instance` | Omitted when absent. |
| anything else | `problem_extensions` | Serialized as top-level members. |

Hooks on a controller including `Problem::Rescuable`:

| hook | for |
|---|---|
| `problem_for(error)` | Adding `instance`, a request id, anything request-derived |
| `around_problem_render(&)` | Locale, or other per-request state the handler needs |
| `report_problem?(error, problem)` | What counts as reportable |
| `report_problem(error, problem)` | Where reports go |
| `render_problem(problem, error)` | Answering in a different shape entirely |

## Caveats

- The top-level constant is `Problem`. Under Zeitwerk, an application with its own
  `Problem` model has a conflict to resolve.
- `i18n` is not a declared dependency. `Problem::I18nable` is autoloaded, so a host that
  never references it never loads it.
- RFC 9457 defines no member for field-level validation errors. Use an extension member.
- `application/problem+xml` is not implemented.

## Development

```
bundle install
bundle exec rake      # specs, then rbs and steep
hk check --all        # rubocop, actionlint, zizmor
hk install            # run the linters on commit
```

## See also

- [DESIGN.md](DESIGN.md) for why the library is shaped this way, and how to derive
  declarations from a problem catalogue of your own.
- [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457.html), the format itself.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sorah/problem.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT). Copyright (c) 2026 Sorah Fukumori.
