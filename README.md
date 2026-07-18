# Z-Functions

[![Zig Version](https://img.shields.io/badge/zig-0.16-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

ECMAScript **functions and arrow functions parser** (ECMA-262 §15, narrowed) in Zig 0.16 — the fourth repo of the JS engine, tying together [z-parser](https://github.com/carlos-sweb/z-parser) (§13, expressions) and [z-statements](https://github.com/carlos-sweb/z-statements) (§14, statements). Part of the [z-*](https://github.com/carlos-sweb) micro-library family.

## Scope: FunctionDeclaration, FunctionExpression, ArrowFunction

Covers `function` declarations, named and anonymous `function` expressions, and arrow functions (both concise-expression-body and block-body forms), with plain-identifier parameters, default values, and a trailing rest parameter. Explicitly **not** generators, async/`await`, classes, or object-literal method/getter/setter shorthand — see [Known gaps](#known-gaps-deferred-to-future-phases).

## The architectural problem this repo solves

Functions and arrow functions are **expressions** — they can appear anywhere in `z-parser`'s grammar, arbitrarily nested (`f(() => 1, x + 1)`). But their **bodies** are statement lists, which is `z-statements`' territory, and `z-statements` already depends on `z-parser`. There's no build-graph cycle (this repo simply depends on both), but `z-parser` needs to be able to produce function-valued expression nodes from inside its own private recursive-descent functions (`parsePrimary`, `parseAssignment`) without knowing about `z-statements` or `z-functions` at compile time.

**Solution: hooks/callbacks**, small additive changes to both upstream repos (matching the pattern already used when `z-statements` needed `z-parser` to expose `pub advance`/`pub expect`/`parseAssignmentExpression`):

- `z-parser` gained `Parser.function_hooks: ?FunctionHooks` (default `null`, zero behavior change when unset), a `.function_like: *anyopaque` `NodeData` variant it never dereferences, and the disambiguation logic itself (`parseAssignment` does a lexer-rewind peek for the bare-identifier arrow form `a => ...`, and a pure token-skipping paren-depth scan for `(...) => ...` — not a speculative real parse, since the existing `(`-expression parser has no way to represent `()` or `(...rest)` to "reinterpret" in the first place).
- `z-statements` gained `Parser.statement_hooks: ?StatementHooks`, a `.function_declaration: *anyopaque` `StatementData` variant, and `pub`-ified `parseBlockStatement`/`parseBindingName`/`parseBindingPattern` (a function body is exactly `{ StatementList }`; a parameter is exactly a `BindingPattern` — identifier or destructuring — reusing the exact same grammar used for `var`/`let`/`const`/`catch`/for-in-of bindings).

## Design

- **Zig's error sets are closed, and the hook function-pointer types are fixed by the upstream repos** — a hook typed `zparser.ParseError!T` cannot `return error.RestParameterMustBeLast` (not a member), nor propagate an ordinary `zstatements.ParseError` like `MissingSemicolon` raised deep inside a function body's `StatementList` (also not a member of the narrower set). This is resolved with a `last_error: ?ParseError` side channel on `Parser`: hook implementations that need to cross into a narrower declared return type stash the real error and return `UnexpectedToken` (a member of every set in play) as a signal; the three public entry points (`parseProgram`/`parseStatement`/`parseExpression`) clear the field on entry and upgrade the signal back to the precise error on the way out. Safe because parsing is strict single-pass recursive descent — once any `try` fails, the whole call chain unwinds immediately before anything else can overwrite the field.
- **`Parser.init` returns `*Parser`, not `Parser` by value** (unlike `z-parser`'s/`z-statements`' own convention) — the hook `ctx: *anyopaque` needs a stable address to reach this repo's own state (`arena`, `last_error`, the wrapped `stmt_parser`), and a by-value return would copy the struct out from under a `ctx` pointer captured during construction. `init` allocates itself directly in the arena instead.
- **Arrow-body dispatch has one classic gotcha that needs no special code**: `x => { a: 1 }` — a bare `{` right after `=>` is *always* a block (here, containing a labelled statement, not an object literal); `x => ({ a: 1 })` is the only legal way to return an object literal, and it "just works" because that `(` goes through `z-parser`'s ordinary primary-expression path.
- **Hook results carry a precise `end` position** (`FunctionHookResult { node: *anyopaque, end: usize }`, not a bare pointer) so the outer `Node`/`Statement` in the caller's tree gets an exact span without ever dereferencing the opaque node.

## Known gaps (deferred to future phases)

- **Generators** (`function*`), **`yield`**.
- **Async/`await`**: `async` stays a plain contextual `.identifier` (per `z-lexer`'s own design); `async function(){}` / `async () => {}` parse permissively into a semantically-wrong-but-non-crashing tree, no special-casing.
- ~~Classes~~ — implemented (§15.7, narrowed): `class name? extends LHS? { ... }` as declaration and expression via two new hooks (`parseClassDeclaration`/`parseClassExpression`), with methods/getters/setters (reusing the phase-9 arity errors), `static` elements (contextual — `static() {}` is still a method named static), keyword and string keys, `;` separators, and the real early errors `MissingClassName`/`DuplicateConstructor`/`ConstructorCannotBeAccessor` (a *static* method named constructor stays legal). Still out of scope: class fields (`x = 1`), `#private` names, computed class-body keys, decorators.
- ~~Object literal method/getter/setter shorthand~~ — implemented: the `parseMethod` hook parses `m() {}` / `get x() {}` / `set x(v) {}` bodies (kind `.method` on `FunctionKind`, never constructable, named after the key), with the real arity early errors as precise variants (`GetterCannotHaveParameters`, `SetterMustHaveExactlyOneParameter`) via the same `last_error` side channel.
- **Rest parameter is identifier-only** (`(...[a, b]) => {}` is legal in real ECMA-262 but rejected here as `Params.rest` stays a plain `BindingName`) — destructuring *parameters* themselves (`function f([a]) {}`, `(a, {b = 1}) => {}`, pattern defaults, whole-param defaults like `({x} = {})`) are fully supported via z-statements' `parseBindingPattern`.
- **`FunctionDeclaration` restricted to StatementList/Block position** (Annex B relaxes this in sloppy mode) — not enforced; no strict-mode tracking exists anywhere in this ecosystem yet.
- **The real `[lookahead ≠ let, async, function, class, @]` early-error and cover-grammar edge cases** around `async` arrow detection specifically — out of scope since async itself is out of scope.

## Usage

```zig
const zfunctions = @import("zfunctions");

var arena_state = std.heap.ArenaAllocator.init(allocator);
defer arena_state.deinit();

const parser = try zfunctions.Parser.init(arena_state.allocator(), "const add = (a, b) => a + b;");
const program = try parser.parseProgram();
```

## Testing

```bash
zig build test
```

## License

MIT
