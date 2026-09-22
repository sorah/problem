# problem

RFC 9457 Problem Details for Rails APIs.

Declare what an error means on the error class. Raise it from anywhere. Every API error
in your app goes out as a consistent `application/problem+json` document, including the
ones raised before your controller runs.

```ruby
class Errors::Forbidden < Errors::ApiError
  type "forbidden"
  status 403
  title "Forbidden"
end

raise Errors::Forbidden.new(detail: "You cannot access this resource")
```

```http
HTTP/1.1 403 Forbidden
Content-Type: application/problem+json

{"type":"forbidden","title":"Forbidden","status":403,"detail":"You cannot access this resource"}
```

## Why

* **One place per error.** Status, title and type live on the class, next to the code that
  raises it, instead of in a mapping table that drifts.
* **Clients get a stable identifier.** `type` is what callers dispatch on, so you can
  reword a title without breaking them.
* **Nothing leaks.** Framework exceptions get the same treatment, and their bodies carry
  the status text rather than the exception message.
* **Small surface.** Two mixins, a middleware and a renderer. Under 250 lines of code, no
  dependency beyond `actionpack`.
* **Typed.** RBS signatures ship with the gem.

## Installation

```ruby
gem "problem"
```

Rails wires itself up. Set the URI prefix your type identifiers live under:

```ruby
# config/application.rb
config.problem.type_prefix = "https://api-probs.example.com/"
```

Outside Rails, call `Problem.install!` and `Problem.configure` yourself.

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

One base class carrying the concern is all it takes. Everything below inherits the
declaration and overrides what it needs.

### 2. Rescue them once

```ruby
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
else is a property of the class, so you declare it once.

## Defining your own

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

That is worth knowing about deliberately. When a caller must not be able to tell two
failures apart, an empty subclass is the whole implementation.

## Catching what escapes the controller

A routing error, an unreadable request body or a failure in middleware never reaches a
controller, so `Problem::Rescuable` never sees it. Wire the exceptions app to cover them:

```ruby
# config/application.rb
config.exceptions_app = Problem::ExceptionsApp.new(
  ActionDispatch::PublicExceptions.new(Rails.public_path),
)
```

Browsers keep getting the static error pages. Everything else gets a problem document,
with the status Rails already mapped the exception to.

## Localized titles

`title` is the only member meant for a human, so it is the only one worth translating.
Override it once on your base class:

```ruby
class Errors::ApiError < StandardError
  include Problem::Detailable

  def self.title(value = nil, interpolations: {})
    return super if value || problem_title

    I18n.t(type.tr("-", "_"), scope: "problem_details.titles", **interpolations)
  end
end
```

```yaml
en:
  problem_details:
    titles:
      not_found: "Not Found"
      forbidden: "Forbidden"
```

A class that spells out a literal `title` keeps it, so you can migrate gradually.

Then establish the locale around rendering:

```ruby
class ApplicationController < ActionController::API
  include Problem::Rescuable

  private def around_problem_render(&) = I18n.with_locale(negotiated_locale, &)
end
```

That wrapper is not optional if you localize. Rails has already unwound your
`around_action` by the time an error renders, so the locale has to be re-established
here. [DESIGN.md](DESIGN.md#localization) has the details.

## Error reporting

5xx problems are reported through `ActiveSupport.error_reporter`, which Sentry and
friends subscribe to. 4xx are not, because an expected client error is not an incident.

To report somewhere else, or to move the line:

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
`retry_after` member to the body.

## Adding your own members

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

To fill `instance`, which identifies the specific occurrence, use the request:

```ruby
private def problem_for(error) = error.to_problem.with(instance: request.fullpath)
```

## Reference

Members of the rendered document:

| member | set by | notes |
|--------|--------|-------|
| `type` | `type "slug"` | Resolved against `type_prefix`. Defaults to `about:blank`. |
| `title` | `title "..."` | Short, human readable, constant for the type. |
| `status` | `status 403` | Always matches the HTTP status. |
| `detail` | `new(detail:)` | Specific to the occurrence. Omitted when absent. |
| `instance` | `problem_instance` | Omitted when absent. |
| anything else | `problem_extensions` | Serialized as top-level members. |

Hooks on a controller including `Problem::Rescuable`:

| hook | for |
|------|-----|
| `problem_for(error)` | Adding `instance`, a request id, anything request-derived |
| `around_problem_render(&)` | Locale, or any per-request state the handler needs |
| `report_problem?(error, problem)` | What counts as reportable |
| `report_problem(error, problem)` | Where reports go |
| `render_problem(problem, error)` | Answering in a different shape entirely |

## Development

```sh
bin/setup
bundle exec rake      # specs, then rbs and steep
hk check --all        # rubocop, actionlint, zizmor
hk install            # run the linters on commit
```

## See also

* [DESIGN.md](DESIGN.md) for why the library is shaped this way, and how to plug a
  problem catalogue into it.
* [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457.html), which obsoletes RFC 7807.
  The format is unchanged; the newer RFC is the one to read.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
