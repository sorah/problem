# Design

Why this library is shaped the way it is. [README.md](README.md) covers using it.

Extracted from a production API, where most of these decisions were paid for once
already.

## The declaration belongs on the error class

The obvious alternative is a central table in `ApplicationController` pairing exception
classes with statuses. It was rejected for three reasons.

It drifts. The table sits far from the code that raises, so an error added in one place
and registered in another eventually stops being registered at all.

It makes adding an error a two-file change, which is the kind of friction that produces
bare `head :forbidden` calls instead.

It has no answer for a subclass that must render exactly as its parent. When telling two
failures apart would leak something (which factor of an authentication attempt failed,
whether a record exists at all), the response has to be byte-identical. With the
declaration inherited, an empty subclass is the entire implementation. With a table, it
is a second entry that has to be kept in sync by hand.

`class_attribute` is what makes a declaration both inherited and overridable. A constant
could not be overridden; an ivar on the singleton class would be invisible to subclasses.

## Two halves, because the controller is not always there

`Problem::Rescuable` is a controller concern. A `rescue_from` handler still has the
controller, so it can reach `request`, the negotiated locale, and whatever a
`before_action` computed. Middleware sees a Rack env and can do none of that.

But an exception raised before dispatch never reaches a controller at all. A routing
error, an unreadable body, a failure in another middleware: no `rescue_from` will ever
run. So `Problem::ExceptionsApp` exists as a separate object, and the two are wired
independently.

`ExceptionsApp` wraps another exceptions app rather than subclassing
`ActionDispatch::PublicExceptions`. A wrapper lets each layer of a stack claim the
requests it recognizes and pass on the rest, which is what makes it composable with, say,
a Connect RPC exceptions app in front of it:

```ruby
config.exceptions_app = ConnectExceptions.new(
  Problem::ExceptionsApp.new(ActionDispatch::PublicExceptions.new(Rails.public_path)),
)
```

A subclass can only ever be the innermost layer, and forces whoever wants the JSON branch
to reimplement the HTML branch they did not want to touch.

Its titles are the status text, never the exception message. A message can quote an id, a
column name or a path, and this is the one place with no controller to have decided what
a caller may see.

## The value object

`Problem::Details` is a frozen `Data` with no Rails in it, so building and serializing a
document needs no controller and no boot.

Extension members merge at the top level because RFC 9457 §3.2 defines them as members of
the problem object, not a nested container. One that shadowed `status` would contradict
the HTTP status in the same response, so a collision raises when the value object is
built rather than at render time inside an error path.

`to_json` is defined explicitly. The generic `Object#to_json` serializes a `Data` as its
inspect output, which is a plausible-looking response body that no assertion on the
status code would catch.

Serialization lives in `Problem::Document`, a module written against readers. A `Data`
cannot gain members by subclassing, so a deployment that wants a *typed* extension member
defines its own `Data` over the member list:

```ruby
TracedProblem = Data.define(*Problem::Details.members, :trace_id) do
  include Problem::Document

  def to_h = super.merge(trace_id:)
end
```

Nothing requires `#to_problem` to return a `Problem::Details`. `Problem::Rescuable` calls
`#status`; the renderer calls `#status` and `#to_json`. That is also how a deployment
keeps rendering through a serializer it already has.

`Details` is written as a `Data.define` assignment reopened as a class, rather than
`class Details < Data.define(...)`. Both rubocop and Steep prefer it: the first flags the
inheritance form, and the second cannot see into a `Data.define` block.

## Type URIs

Resolution happens in `Detailable#to_problem`, not in `Details.new`. That keeps the value
object pure, so a document built by hand is never rewritten behind the caller's back.

| declared `type` | result |
|---|---|
| `nil` | serialized as `about:blank` |
| `"about:blank"` | returned untouched |
| carries a scheme | returned untouched, it is already absolute |
| anything else | prefixed, or left alone when no prefix is set |

`about:blank` is special-cased because prefixing it produces a URI that looks valid and
identifies nothing, and it is the one `type` value the RFC assigns a meaning to.

Leaving a slug unprefixed is legal: RFC 9457 defines `type` as a URI *reference*, not a
URI. The prefix exists so sixty error classes do not each repeat an authority, which is
sixty chances to typo it.

## Plugging in a problem catalogue

A deployment that keeps its problems in a registry (an enum, a YAML file, a table) wants
type, status and title derived from it. `Problem::I18nable` is the shipped example of the
simple case, overriding `title` in a `ClassMethods` that sits ahead of the DSL. When the
catalogue layer is its own concern, prepend a module to the error class's singleton and
call `super` for anything it does not cover:

```ruby
module Typeable
  extend ActiveSupport::Concern

  module Derivation
    def type(value = nil)
      return super if value || problem_type.nil?

      CATALOGUE.fetch(problem_type).fetch(:type)
    end
  end

  included { singleton_class.prepend(Derivation) }
end
```

A prepend rather than a pluggable resolver object. A resolver would bless one catalogue
shape, add global mutable state, and not compose with inheritance. `prepend` and `super`
compose for free, and a class that wants a literal declaration simply makes one.

Five things make this work, none of them visible at a call site. They are the real public
contract of `Problem::Detailable`, and each fails silently rather than loudly:

1. `ClassMethods` is attached with `extend`, so a singleton prepend sits ahead of it.
2. The signatures stay `status(value = nil)`, `type(value = nil)` and
   `title(value = nil, interpolations: {})`. The keyword *name* `interpolations:` is
   load-bearing: a derivation calls `super` with it, and renaming it raises only while
   rendering an error, in production, on a response that was already an error.
3. Those three are never defined on the including class itself, only in `ClassMethods`,
   or the prepend stops winning.
4. `#to_problem` reaches them through `self.class` rather than reading the class
   attributes behind them. Reading `problem_uri` directly is a one-word change that
   disables the whole derivation layer with no error anywhere.
5. The catalogue layer is included *before* `Problem::Detailable`. Included after, its
   fallbacks shadow the real DSL and every literal declaration reads back `nil`.

And one more, which is the trap people actually hit: extending a `ClassMethods` onto a
subclass puts it *ahead* of the prepend its superclass holds. A concern that mixes in a
catalogue layer has to re-apply the prepend itself, on every inclusion.

`spec/problem/detailable_derivation_spec.rb` builds the whole arrangement and pins it,
including both silent failure modes. Without that spec the extraction is one refactor
away from breaking quietly.

### Why I18nable needs none of that ceremony

`Problem::I18nable` overrides the same method and is a plain `ActiveSupport::Concern`,
with no prepend at all. It gets away with it by declaring `include Detailable` as a
concern dependency: `ActiveSupport::Concern` then includes `Detailable` first and extends
`I18nable::ClassMethods` afterwards, which puts it ahead in the singleton ancestry and
leaves `super` pointing at the literal DSL. Re-including `Detailable` explicitly, in
either order, changes nothing, because a module already in the ancestry is not moved.

The prepend is only needed when the layer supplies terminal fallbacks of its own, as a
catalogue concern does. `I18nable` supplies none; it defers to `super`.

`i18n` is not a declared dependency of the gem, so `Problem::I18nable` is autoloaded
rather than required. A host that never references the constant never loads `i18n`
through it.

## Rendering

One `rescue_from`, registered against `Problem::Detailable` itself. A Module is matched
with `===`, so a single registration covers every error class that mixed it in.

The handler is split into named steps so a deployment overrides the one it needs, and so
a different transport replaces only `#render_problem`. A Connect RPC controller carries
the document as an error detail and answers in the protocol's own shape; nothing else
about the handler changes.

### Localization

The gem never calls `I18n`. `around_problem_render` is the seam, and it wraps the whole
handler rather than just the render for a reason worth writing down:
`ActionController::Rescue` wraps `AbstractController::Callbacks`, so an `around_action`
that established the locale has **already unwound** by the time a `rescue_from` handler
runs. The title lookup happens while the problem is being built, not while it renders, so
wrapping only the render would miss it.

### Reporting

`rescue_from` swallows the exception. Nothing logs it, and no error reporter's automatic
capture sees it, which is a quiet way to lose every 5xx an API returns.

Reports go through `ActiveSupport.error_reporter`, the registry Rails error reporters
subscribe to, rather than naming a vendor. 4xx are not reported: an expected client error
is not an incident.

## Initialization

A Railtie, because that is what Rails offers for exactly this, instead of an initializer
every host copies. The same work is a plain `Problem.install!` for a Rack host or a spec
that never boots Rails, which is how this gem's own suite reaches it.

`problem.config` declares `after: :load_config_initializers`. A railtie initializer
otherwise runs before `config/initializers` is loaded, which would make
`config.problem.type_prefix` silently do nothing when set in the file an application
would most expect to set it in.

The renderer takes the status from the object it is handed and calls `to_json` on it,
requiring nothing more. That is what lets a deployment render through its own serializer.

The Railtie deliberately does not touch `config.exceptions_app`. Replacing what an
application set there is not an initializer's business.

## Types

Signatures are inline `#:` annotations generated into `sig/generated`, which is checked
in. CI asserts it is current with `git diff --exit-code`, because an annotation can change
without anyone running `rake rbs`, and a stale signature means the type check is checking
a shape the code no longer has.

`sig/manual` holds what inline annotations cannot express:

* the self-type of a mix-in, since `Problem::Rescuable` needs `render` and `response` from
  whatever controller it lands in, and `Problem::Detailable` needs its own class-level DSL;
* the accessors `class_attribute` installs at runtime;
* `Problem::Details`, since a `Data.define` assignment has no inferable shape;
* a `Data#initialize` stub, because core RBS declares none and a subclass overriding it
  has nothing to call `super` on.

Three DSL blocks are marked `steep:ignore`: `included do`, and the renderer registration.
Their `self` is supplied by Rails at runtime and cannot be named in RBS. `class_methods do`
was avoided entirely in favour of a nested `ClassMethods` module, which is ordinary code
that Steep can check and which `ActiveSupport::Concern` picks up by name.

## Layout

```
lib/problem/document.rb        to_h / as_json / to_json, and the media type
lib/problem/details.rb         the value object
lib/problem/detailable.rb      the class-level DSL, and #to_problem
lib/problem/i18nable.rb        titles from I18n, autoloaded
lib/problem/retry_after.rb     Retry-After, as a worked example of the hooks
lib/problem/rescuable.rb       rescue_from, split into overridable steps
lib/problem/exceptions_app.rb  the config.exceptions_app wrapper
lib/problem/renderer.rb        the application/problem+json renderer
lib/problem/railtie.rb         required only when Rails is present
sig/manual/                    what RBS cannot infer
```

## Deliberately out of scope

* A catalogue of problem types, and anything that reads one. The seam is above.
* `Accept-Language` negotiation. `Problem::I18nable` translates a title once a locale is
  set; choosing that locale is the application's job, and `around_problem_render` is
  where it plugs in.
* Validation-error serialization. RFC 9457 defines no `errors` member; use an extension.
* `application/problem+xml`.
* Anything Connect or gRPC. `render_problem` is the seam, and
  [connect_rpc_rails](https://github.com/ivry-inc/connect_rpc_rails) is the other half.

## A note on the name

The top-level constant is `Problem`, generic enough to collide with a `Problem` model in
a host application. Nothing here reopens or autoloads anything outside `Problem::`, but
under Zeitwerk a same-named application constant is a conflict you would have to resolve.
