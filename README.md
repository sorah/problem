# problem

RFC 9457 Problem Details for Rails APIs. The exception *is* the description of the
problem: an error class declares its type, title and status, and one controller concern
renders any of them as `application/problem+json`.

RFC 9457 obsoletes RFC 7807, which is what most of the prose about problem details still
says. The format is unchanged; the newer RFC is the one to read.

Extracted from a production API, with its test suite.

## How it works

Declare the problem where the error is defined:

```ruby
module Errors
  class Forbidden < StandardError
    include Problem::Detailable

    type "forbidden"
    status 403
    title "Forbidden"
  end
end
```

Rescue them once:

```ruby
class ApplicationController < ActionController::API
  include Problem::Rescuable
end
```

Raise one from anywhere the controller can reach:

```ruby
raise Errors::Forbidden.new(detail: "You cannot access this resource")
```

```http
HTTP/1.1 403 Forbidden
Content-Type: application/problem+json

{"type":"forbidden","title":"Forbidden","status":403,"detail":"You cannot access this resource"}
```

**The problem is declared on the error class, not in a mapping table.** The alternative —
a central hash in `ApplicationController` pairing exception classes with statuses — drifts
from the raise site, makes adding an error a two-file change, and gives a subclass no way
to say "render me exactly as my parent". That last one is a real requirement: when a
caller must not be able to tell two failures apart, `class ConfidentialClientRequired <
AuthenticationRequired; end` declaring nothing is the whole implementation.

**A controller concern for the errors a controller raises, and a middleware for the ones
that escape it.** A `rescue_from` handler still has the controller: `request`, the
negotiated locale, whatever a `before_action` computed. Middleware sees a Rack env and can
neither localize nor decorate. But an exception raised before dispatch — a routing error,
an unreadable body, a failure in another middleware — never reaches a controller at all,
so the two halves are different objects on purpose. See
[Escaped exceptions](#escaped-exceptions).

## What goes on the wire

| member | required | what this gem does |
|---|---|---|
| `type` | yes | A URI reference identifying the problem. Renders `about:blank` when the class declares none. |
| `title` | no | A short human-readable summary, constant for the type. |
| `status` | yes | Always equal to the HTTP status, because the renderer takes one from the other. |
| `detail` | no | Specific to this occurrence, so it is a constructor argument rather than a declaration. |
| `instance` | no | A URI for this occurrence. Only the request can supply it — see `problem_for`. |
| extension members | no | Anything else, serialized as top-level members (RFC 9457 §3.2). |

An absent member is omitted rather than sent as `null`, so a client tests presence rather
than emptiness.

## Declaring a problem

`status`, `title` and `type` are class-level because they describe the problem type.
`detail` is per-occurrence because RFC 9457 defines it that way.

**Declarations are inherited and overridable**, which is `class_attribute`'s doing: a
constant could not be overridden, and an ivar on the singleton class would be invisible to
subclasses.

**`type_prefix` exists so a class declares a slug rather than a URL.** The authority in a
type URI is a deployment fact; repeating `https://api-probs.example.com/` on sixty error
classes is sixty chances to typo it.

```ruby
Problem.configure { |c| c.type_prefix = "https://api-probs.example.com/" }
# or, in a Rails app:
config.problem.type_prefix = "https://api-probs.example.com/"
```

`about:blank` and anything already carrying a URI scheme are left alone. With no prefix
configured a slug goes out as-is, which is legal: RFC 9457 defines `type` as a URI
*reference*.

Two hooks let an occurrence add to its own document:

```ruby
class Throttled < StandardError
  include Problem::Detailable
  include Problem::RetryAfter

  status 429
  title "Try again in %{retry_after} seconds"
end

raise Throttled.new(retry_after: 30)
```

`Problem::RetryAfter` is the worked example of both: it fills `title_interpolations` and
`problem_extensions`, and adds a `Retry-After` response header through `problem_headers`.

## Deriving from a catalogue

A deployment that keeps its problems in one place — an enum, a YAML file, a table — wants
type, status and title to come from there, with titles translated. Prepend a module to the
error class's singleton and call `super` for anything the catalogue does not cover:

```ruby
module Typeable
  extend ActiveSupport::Concern

  module Derivation
    def type(value = nil)
      return super if value || problem_type.nil?

      CATALOGUE.fetch(problem_type).fetch(:type)
    end

    def title(value = nil, interpolations: {})
      return super if value || problem_type.nil?

      I18n.t(problem_type, scope: "problem_details.titles", **interpolations)
    end
  end

  included { singleton_class.prepend(Derivation) }
end
```

**A prepend rather than a pluggable resolver object.** A resolver would bless one
catalogue shape, add global mutable state, and not compose with inheritance. `prepend` +
`super` composes for free, and a class that wants a literal declaration just makes one.

Three things make it work, and none are visible at a call site: `ClassMethods` is attached
with `extend`, so a singleton prepend sits ahead of it; this gem never defines `type`,
`status` or `title` on the including class itself; and `#to_problem` reaches them through
`self.class` rather than reading the class attributes behind them. `interpolations:` is
part of `title`'s signature for exactly this reason.

Two traps worth knowing, both of which fail silently. The prepend has to be re-applied by
every concern that mixes the catalogue layer in, because extending a `ClassMethods` onto a
subclass puts it *ahead* of the prepend its superclass holds. And the catalogue layer must
be included *before* `Problem::Detailable`, or its fallbacks shadow the real DSL.
`spec/problem/detailable_derivation_spec.rb` holds all of it.

## Rendering, and the hooks

`Problem::Rescuable` registers one `rescue_from Problem::Detailable` — a Module, matched
with `===`, which is what makes one registration cover every class that mixed the concern
in. Each step of the handler is its own method:

| you want to | override |
|---|---|
| fill `instance`, add a request id | `problem_for(error)` |
| render in the caller's language | `around_problem_render(&)` |
| decide what counts as reportable | `report_problem?(error, problem)` |
| send it somewhere other than the error reporter | `report_problem(error, problem)` |
| answer in another shape entirely | `render_problem(problem, error)` |

**Localization is a wrapper, not a dependency.** This gem never calls `I18n`:

```ruby
private def around_problem_render(&) = I18n.with_locale(negotiated_locale, &)
```

It has to be a wrapper around the whole handler rather than around the render, and this is
the part that costs people a bug: `ActionController::Rescue` wraps
`AbstractController::Callbacks`, so an `around_action` that set the locale has **already
unwound** by the time a `rescue_from` handler runs. The title lookup happens inside
`problem_for`, so the wrapper must cover that too.

**A rescued exception is invisible to error reporting.** `rescue_from` swallows it, so
nothing logs it and no reporter's automatic capture sees it. This gem reports 5xx problems
through `ActiveSupport.error_reporter` — the registry Sentry and friends subscribe to — and
leaves 4xx alone, because an expected client error is not an incident. Reporting to one
vendor directly is a `report_problem` override.

## Escaped exceptions

```ruby
config.exceptions_app = Problem::ExceptionsApp.new(
  ActionDispatch::PublicExceptions.new(Rails.public_path),
)
```

It answers non-browser requests as `application/problem+json` and hands everything else to
the app it wraps, which keeps owning the HTML error pages. The status comes from
`ActionDispatch::ExceptionWrapper`, so `rescue_responses` stays the one place an
application classifies an exception, and the title is the status's own text — **never the
exception's message**, which can quote an id, a column name, a path. A `Problem::Detailable`
that escaped renders under its own declaration. Override `problem_for` to publish a type
from a catalogue.

**A wrapper rather than an `ActionDispatch::PublicExceptions` subclass**, so a deployment
can chain layers that each claim what they recognize. A subclass can only ever be the
innermost one, and forces you to reimplement the HTML branch you did not want to touch.

## Design highlights

- **A frozen value object with no Rails in it.** `Problem::Details` is a `Data`; building
  and serializing a document needs no controller, no request, and no boot.
- **No configuration object to speak of, and no initializer to copy.** Every knob is a
  class declaration or a method override; the Railtie does the wiring.
- **`ActionController::API`-safe.** Nothing view-shaped, no ActionView.
- **One `rescue_from`, on a module.** An application's more specific `rescue_from`
  registered afterwards still wins, because Rails picks the most recently registered
  handler.
- **Typed.** RBS signatures are checked in and verified in CI.

## Extending the document

The `extensions` hash covers most of it. For a typed value object, define your own `Data`
over the member list — a `Data` cannot gain members by subclassing, so this is the seam
rather than inheritance:

```ruby
TracedProblem = Data.define(*Problem::Details.members, :trace_id) do
  include Problem::Document

  def to_h = super.merge(trace_id:)
end
```

Nothing requires `#to_problem` to return a `Problem::Details`: `Problem::Rescuable` calls
`#status`, and the renderer calls `#status` and `#to_json`. That is also how a deployment
keeps rendering through its own serializer.

## Layout

```
lib/problem/document.rb        to_h / as_json / to_json, and the media type
lib/problem/details.rb         the value object
lib/problem/detailable.rb      the class-level DSL, and #to_problem
lib/problem/retry_after.rb     Retry-After, as a worked example of the hooks
lib/problem/rescuable.rb       rescue_from, split into overridable steps
lib/problem/exceptions_app.rb  the config.exceptions_app wrapper
lib/problem/renderer.rb        the application/problem+json renderer
lib/problem/railtie.rb         required only when Rails is present
sig/manual/                    what RBS cannot infer; see Types
```

## Run

```sh
bundle exec rspec        # the suite
bundle exec rake         # rspec, then rbs + steep
bundle exec rake rbs     # regenerate sig/generated
hk check --all           # rubocop, actionlint, zizmor
hk install               # run the linters on commit
rdoc --coverage-report lib
```

## Types

Signatures are inline `#:` annotations, generated into `sig/generated` with `rbs-inline`.
That directory is checked in and CI asserts it is current with `git diff --exit-code`,
because an annotation can change without anyone running `rake rbs`, which would leave the
type check checking the wrong shape.

`sig/manual` holds the three things inline annotations cannot express: the self-type of a
mix-in (`Problem::Rescuable` needs `render` and `response` from the controller it lands
in), the accessors `class_attribute` installs at runtime, and `Problem::Details` itself,
since a `Data.define` assignment has no inferable shape. Dependency signatures come from
`rbs collection install`.

## Deliberately out of scope

- A catalogue of problem types, and anything that reads one. The seam is documented above.
- `Accept-Language` negotiation. `around_problem_render` is where yours plugs in.
- Validation-error serialization. RFC 9457 defines no `errors` member; use an extension.
- `application/problem+xml`.
- Anything Connect or gRPC. `render_problem` is the seam, and
  [connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) is the other half.

## A note on the name

The top-level constant is `Problem`, which is generic enough to collide with a `Problem`
model in a host application. Nothing here reopens or autoloads anything outside
`Problem::`, but under Zeitwerk a same-named application constant is a conflict you would
have to resolve.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
