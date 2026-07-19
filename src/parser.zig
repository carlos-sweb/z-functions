const std = @import("std");
const Allocator = std.mem.Allocator;
const zlexer = @import("zlexer");
const zparser = @import("zparser");
const zstatements = @import("zstatements");
const ast = @import("ast.zig");

pub const ParseError = error{
    /// A FunctionDeclaration (statement position) had no name -- e.g.
    /// `function () {}` typed as a statement. Real ECMA-262 requires a name
    /// there outside default-export contexts; modules are out of scope
    /// project-wide, so a name is required unconditionally.
    MissingFunctionName,
    /// A `...name` rest parameter was not immediately followed by `)`.
    /// Covers all three real-spec violations with one variant: another
    /// parameter after it (`(...a, b)`), a default value on it
    /// (`(...a = 1)`), and a trailing comma after it specifically
    /// (`(a, ...b,)` -- unlike ordinary trailing commas, which ARE allowed
    /// after regular params).
    RestParameterMustBeLast,
    /// `{ get x(a) {} }` -- getters take no parameters (real early error).
    GetterCannotHaveParameters,
    /// `{ set x() {} }` / `{ set x(a, b) {} }` / `{ set x(...a) {} }` --
    /// setters take exactly one non-rest parameter (real early error).
    SetterMustHaveExactlyOneParameter,
    /// A ClassDeclaration (statement position) had no name -- same rule
    /// (and same rationale) as MissingFunctionName.
    MissingClassName,
    /// Two non-static `constructor(...)` elements in one class body.
    DuplicateConstructor,
    /// `get constructor()` / `set constructor(v)` (non-static) -- the
    /// real spec forbids the constructor being an accessor.
    ConstructorCannotBeAccessor,
} || zstatements.ParseError;

pub const Parser = struct {
    stmt_parser: zstatements.Parser,
    arena: Allocator,
    /// Side channel for precise z-functions-only (or z-statements-wide)
    /// errors raised inside a hook whose declared return type -- fixed by
    /// z-parser/z-statements -- can't name them. Zig error sets are closed:
    /// a hook typed `zparser.ParseError!T` cannot `return
    /// error.RestParameterMustBeLast` (not a member), nor can it propagate
    /// an ordinary `zstatements.ParseError` like `MissingSemicolon` raised
    /// deep inside a function body's StatementList (also not a member of
    /// the narrower `zparser.ParseError`). Every such error is stashed here
    /// and the hook returns `UnexpectedToken` (a member of every set in
    /// play) as a signal value; the public entry points below clear this
    /// field on entry and upgrade the signal back to the precise error on
    /// the way out. Safe because parsing here is strict single-pass
    /// recursive descent: once a `try` fails anywhere, the whole call chain
    /// unwinds immediately, so nothing can overwrite this field before the
    /// entry point consults it.
    last_error: ?ParseError = null,

    pub fn init(arena: Allocator, source: []const u8) ParseError!*Parser {
        const self = try arena.create(Parser);
        self.* = .{
            .stmt_parser = try zstatements.Parser.init(arena, source),
            .arena = arena,
        };
        self.stmt_parser.expr_parser.function_hooks = .{
            .ctx = self,
            .parseArrowFunction = arrowFunctionHook,
            .parseFunctionExpression = functionExpressionHook,
            .parseMethod = methodHook,
            .parseClassExpression = classExpressionHook,
        };
        self.stmt_parser.statement_hooks = .{
            .ctx = self,
            .parseFunctionDeclaration = functionDeclarationHook,
            .parseClassDeclaration = classDeclarationHook,
        };
        return self;
    }

    // ===== Entry points =====

    pub fn parseProgram(self: *Parser) ParseError![]const *zstatements.Statement {
        self.last_error = null;
        return self.stmt_parser.parseProgram() catch |err| {
            if (self.last_error) |precise| return precise;
            return err;
        };
    }

    pub fn parseStatement(self: *Parser) ParseError!*zstatements.Statement {
        self.last_error = null;
        return self.stmt_parser.parseStatement() catch |err| {
            if (self.last_error) |precise| return precise;
            return err;
        };
    }

    pub fn parseExpression(self: *Parser) ParseError!*zparser.Node {
        self.last_error = null;
        return self.stmt_parser.expr_parser.parseExpression() catch |err| {
            if (self.last_error) |precise| return precise;
            return err;
        };
    }

    // ===== Shared parameter-list / arrow-body grammar =====
    // Typed to z-functions' own (widest) ParseError -- these are internal
    // helpers, not hook callbacks, so nothing constrains their error set.
    // Plain `try` works throughout, including for this repo's own new
    // variants.

    /// `(` (BindingPattern ('=' AssignmentExpression)? (',' same)*)? (',' '...' BindingIdentifier)? ')`
    fn parseParams(self: *Parser, parser: *zparser.Parser) ParseError!ast.Params {
        _ = try parser.expect(.punct_lparen);
        var items: std.ArrayList(ast.Param) = .empty;
        var rest: ?ast.RestParam = null;
        while (parser.current.type != .punct_rparen) {
            if (parser.current.type == .punct_ellipsis) {
                try parser.advance(); // '...'
                const binding = try self.stmt_parser.parseBindingName();
                if (parser.current.type != .punct_rparen) return ParseError.RestParameterMustBeLast;
                rest = binding;
                break;
            }
            const pattern = try self.stmt_parser.parseBindingPattern();
            var default: ?*zparser.Node = null;
            if (parser.current.type == .punct_assign) {
                try parser.advance();
                default = try parser.parseAssignmentExpression();
            }
            try items.append(self.arena, .{ .pattern = pattern, .default = default });
            if (parser.current.type != .punct_rparen) _ = try parser.expect(.punct_comma);
        }
        _ = try parser.expect(.punct_rparen);
        return .{ .items = try items.toOwnedSlice(self.arena), .rest = rest };
    }

    fn parseArrowBody(self: *Parser, parser: *zparser.Parser) ParseError!ast.FunctionBody {
        if (parser.current.type == .punct_lbrace) {
            return .{ .block = try self.stmt_parser.parseBlockStatement() };
        }
        return .{ .expression = try parser.parseAssignmentExpression() };
    }

    // ===== Class grammar (ECMA-262 section 15.7, narrowed) =====

    /// Identifier, keyword (`delete() {}` is a legal method name), or
    /// string-literal keys. Computed class-body keys are out of scope for
    /// this phase (object literals do have them).
    fn parseClassElementKey(self: *Parser, parser: *zparser.Parser) ParseError![]const u8 {
        _ = self;
        const tok = parser.current;
        switch (tok.type) {
            .identifier => {
                const text = tok.owned_value orelse tok.lexeme;
                try parser.advance();
                return text;
            },
            .string_literal => {
                const v = tok.owned_value orelse tok.lexeme[1 .. tok.lexeme.len - 1];
                try parser.advance();
                return v;
            },
            else => {
                if (zlexer.keywordFromLexeme(tok.lexeme) != null) {
                    try parser.advance();
                    return tok.lexeme;
                }
                return ParseError.UnexpectedToken;
            },
        }
    }

    /// `(params) { body }` for one class element, with the same accessor
    /// arity early errors the object-literal methodHook enforces. Always
    /// a `.method`-kind FunctionNode (non-constructable, named).
    fn parseClassMethodBody(self: *Parser, parser: *zparser.Parser, kind: ast.ClassElementKind, name: []const u8, is_generator: bool, is_async: bool) ParseError!*ast.FunctionNode {
        const start = parser.current.start;
        // Params never allow yield/await; the body does per the method's
        // generator/async-ness.
        const saved_flags = setBodyFlags(parser, false, false);
        defer {
            parser.yield_allowed = saved_flags.y;
            parser.await_allowed = saved_flags.a;
        }
        const params = try self.parseParams(parser);
        switch (kind) {
            .get => if (params.items.len != 0 or params.rest != null) return ParseError.GetterCannotHaveParameters,
            .set => if (params.items.len != 1 or params.rest != null) return ParseError.SetterMustHaveExactlyOneParameter,
            .method => {},
        }
        parser.yield_allowed = is_generator;
        parser.await_allowed = is_async;
        const body_stmt = try self.stmt_parser.parseBlockStatement();
        const node = try self.arena.create(ast.FunctionNode);
        node.* = .{
            .start = start,
            .end = body_stmt.end,
            .kind = .{ .method = .{ .name = name } },
            .params = params,
            .body = .{ .block = body_stmt },
            .is_generator = is_generator,
            .is_async = is_async,
        };
        return node;
    }

    /// `class name? (extends LHSExpr)? { ( ';' | 'static'? ('get'|'set')?
    /// key '(' params ')' '{' body '}' )* }`. `static`/`get`/`set` are
    /// contextual: each stays an ordinary method name when `(` follows
    /// (`static() {}`, `get() {}`), same one-token lookahead as object
    /// literals. The `extends` clause is parsed permissively as an
    /// AssignmentExpression (a superset of the spec's
    /// LeftHandSideExpression) -- it naturally stops at the body's `{`.
    fn parseClass(self: *Parser, parser: *zparser.Parser, require_name: bool) ParseError!*ast.ClassNode {
        const start = parser.current.start;
        try parser.advance(); // 'class'

        var name: ?[]const u8 = null;
        if (parser.current.type == .identifier) {
            const binding = try self.stmt_parser.parseBindingName();
            name = binding.name;
        } else if (require_name) {
            return ParseError.MissingClassName;
        }

        var superclass: ?*zparser.Node = null;
        if (parser.current.type == .keyword_extends) {
            try parser.advance();
            superclass = try parser.parseAssignmentExpression();
        }

        _ = try parser.expect(.punct_lbrace);
        var elements: std.ArrayList(ast.ClassElement) = .empty;
        var seen_constructor = false;
        while (parser.current.type != .punct_rbrace) {
            if (parser.current.type == .punct_semi) {
                try parser.advance();
                continue;
            }

            var is_static = false;
            if (parser.current.type == .identifier and
                std.mem.eql(u8, parser.current.owned_value orelse parser.current.lexeme, "static") and
                (try parser.peekNextType()) != .punct_lparen)
            {
                is_static = true;
                try parser.advance();
            }

            // `async` / `*` method prefixes (contextual `async`, same
            // one-token lookahead as static/get/set).
            var is_async = false;
            var is_generator = false;
            if (parser.current.type == .identifier and
                std.mem.eql(u8, parser.current.owned_value orelse parser.current.lexeme, "async") and
                (try parser.peekNextType()) != .punct_lparen)
            {
                is_async = true;
                try parser.advance();
            }
            if (parser.current.type == .punct_star) {
                is_generator = true;
                try parser.advance();
            }

            var kind: ast.ClassElementKind = .method;
            if (!is_generator and !is_async and parser.current.type == .identifier) {
                const lex = parser.current.owned_value orelse parser.current.lexeme;
                const acc: ?ast.ClassElementKind = if (std.mem.eql(u8, lex, "get"))
                    .get
                else if (std.mem.eql(u8, lex, "set"))
                    .set
                else
                    null;
                if (acc != null and (try parser.peekNextType()) != .punct_lparen) {
                    kind = acc.?;
                    try parser.advance();
                }
            }

            const key = try self.parseClassElementKey(parser);
            if (!is_static and std.mem.eql(u8, key, "constructor")) {
                // (A *static* method named constructor is legal, per spec.)
                if (kind != .method or is_generator or is_async) return ParseError.ConstructorCannotBeAccessor;
                if (seen_constructor) return ParseError.DuplicateConstructor;
                seen_constructor = true;
            }

            const fnode = try self.parseClassMethodBody(parser, kind, key, is_generator, is_async);
            try elements.append(self.arena, .{ .kind = kind, .key = key, .is_static = is_static, .function = fnode });
        }
        const end = parser.current.end;
        try parser.advance(); // '}'

        const cnode = try self.arena.create(ast.ClassNode);
        cnode.* = .{
            .start = start,
            .end = end,
            .name = name,
            .superclass = superclass,
            .elements = try elements.toOwnedSlice(self.arena),
        };
        return cnode;
    }
};

fn selfFromCtx(ctx: *anyopaque) *Parser {
    return @ptrCast(@alignCast(ctx));
}

fn arrowFunctionHook(ctx: *anyopaque, parser: *zparser.Parser) zparser.ParseError!zparser.FunctionHookResult {
    const self = selfFromCtx(ctx);
    const start = parser.current.start;
    // `async` arrow: z-parser routed us here with current at `async`.
    var is_async = false;
    if (parser.current.type == .identifier and
        std.mem.eql(u8, parser.current.owned_value orelse parser.current.lexeme, "async"))
    {
        is_async = true;
        parser.advance() catch |err| {
            self.last_error = err;
            return zparser.ParseError.UnexpectedToken;
        };
    }
    // Params never allow yield/await; an async arrow's body allows await
    // (arrows are never generators).
    const saved_flags = setBodyFlags(parser, false, false);
    defer {
        parser.yield_allowed = saved_flags.y;
        parser.await_allowed = saved_flags.a;
    }
    var params: ast.Params = undefined;
    if (parser.current.type == .punct_lparen) {
        params = self.parseParams(parser) catch |err| {
            self.last_error = err;
            return zparser.ParseError.UnexpectedToken;
        };
    } else {
        const binding = self.stmt_parser.parseBindingName() catch |err| {
            self.last_error = err;
            return zparser.ParseError.UnexpectedToken;
        };
        const id = try self.arena.create(zstatements.BindingPattern);
        id.* = .{ .identifier = binding };
        const single = try self.arena.dupe(ast.Param, &.{.{ .pattern = id, .default = null }});
        params = .{ .items = single, .rest = null };
    }
    _ = try parser.expect(.punct_arrow);
    parser.await_allowed = is_async;
    const body = self.parseArrowBody(parser) catch |err| {
        self.last_error = err;
        return zparser.ParseError.UnexpectedToken;
    };
    const node = try self.arena.create(ast.FunctionNode);
    node.* = .{ .start = start, .end = ast.functionBodyEnd(body), .kind = .arrow, .params = params, .body = body, .is_async = is_async };
    return .{ .node = node, .end = node.end };
}

/// Consumes the optional `async` (contextual identifier) and, after
/// `function`, the optional `*` -- shared by both function hooks. The
/// caller guarantees `async` is only present when `function` follows.
fn parseFunctionFlags(parser: *zparser.Parser) zparser.ParseError!struct { is_async: bool, is_generator: bool } {
    var is_async = false;
    if (parser.current.type == .identifier) {
        // Only ever reached with 'async' as the current identifier.
        is_async = true;
        try parser.advance();
    }
    _ = try parser.expect(.keyword_function);
    var is_generator = false;
    if (parser.current.type == .punct_star) {
        is_generator = true;
        try parser.advance();
    }
    return .{ .is_async = is_async, .is_generator = is_generator };
}

const SavedFlags = struct { y: bool, a: bool };

/// yield/await are grammatical strictly per-body: parameters never allow
/// them, and a nested non-generator/non-async body turns them back off.
/// Returns the previous flags for the caller's defer-restore.
fn setBodyFlags(parser: *zparser.Parser, is_generator: bool, is_async: bool) SavedFlags {
    const saved: SavedFlags = .{ .y = parser.yield_allowed, .a = parser.await_allowed };
    parser.yield_allowed = is_generator;
    parser.await_allowed = is_async;
    return saved;
}

fn functionExpressionHook(ctx: *anyopaque, parser: *zparser.Parser) zparser.ParseError!zparser.FunctionHookResult {
    const self = selfFromCtx(ctx);
    const start = parser.current.start;
    const flags = try parseFunctionFlags(parser);
    var name: ?[]const u8 = null;
    if (parser.current.type == .identifier) {
        const binding = self.stmt_parser.parseBindingName() catch |err| {
            self.last_error = err;
            return zparser.ParseError.UnexpectedToken;
        };
        name = binding.name;
    }
    const saved_params = setBodyFlags(parser, false, false);
    const params = self.parseParams(parser) catch |err| {
        parser.yield_allowed = saved_params.y;
        parser.await_allowed = saved_params.a;
        self.last_error = err;
        return zparser.ParseError.UnexpectedToken;
    };
    parser.yield_allowed = flags.is_generator;
    parser.await_allowed = flags.is_async;
    defer {
        parser.yield_allowed = saved_params.y;
        parser.await_allowed = saved_params.a;
    }
    const body_stmt = self.stmt_parser.parseBlockStatement() catch |err| {
        self.last_error = err;
        return zparser.ParseError.UnexpectedToken;
    };
    const node = try self.arena.create(ast.FunctionNode);
    node.* = .{
        .start = start,
        .end = body_stmt.end,
        .kind = .{ .function_expr = .{ .name = name } },
        .params = params,
        .body = .{ .block = body_stmt },
        .is_generator = flags.is_generator,
        .is_async = flags.is_async,
    };
    return .{ .node = node, .end = node.end };
}

fn methodHook(ctx: *anyopaque, parser: *zparser.Parser, kind: zparser.MethodKind, name: []const u8, is_generator: bool, is_async: bool) zparser.ParseError!zparser.FunctionHookResult {
    const self = selfFromCtx(ctx);
    const start = parser.current.start;
    // Params never allow yield/await; the body does, per the method's
    // own generator/async-ness.
    const saved_flags = setBodyFlags(parser, false, false);
    defer {
        parser.yield_allowed = saved_flags.y;
        parser.await_allowed = saved_flags.a;
    }
    const params = self.parseParams(parser) catch |err| {
        self.last_error = err;
        return zparser.ParseError.UnexpectedToken;
    };
    // Real early errors: getters take no parameters, setters exactly one
    // (rest included in "no"/"one" -- `set x(...a)` is a SyntaxError too).
    switch (kind) {
        .get => if (params.items.len != 0 or params.rest != null) {
            self.last_error = ParseError.GetterCannotHaveParameters;
            return zparser.ParseError.UnexpectedToken;
        },
        .set => if (params.items.len != 1 or params.rest != null) {
            self.last_error = ParseError.SetterMustHaveExactlyOneParameter;
            return zparser.ParseError.UnexpectedToken;
        },
        .method => {},
    }
    parser.yield_allowed = is_generator;
    parser.await_allowed = is_async;
    const body_stmt = self.stmt_parser.parseBlockStatement() catch |err| {
        self.last_error = err;
        return zparser.ParseError.UnexpectedToken;
    };
    const node = try self.arena.create(ast.FunctionNode);
    node.* = .{
        .start = start,
        .end = body_stmt.end,
        .kind = .{ .method = .{ .name = name } },
        .params = params,
        .body = .{ .block = body_stmt },
        .is_generator = is_generator,
        .is_async = is_async,
    };
    return .{ .node = node, .end = node.end };
}

fn classExpressionHook(ctx: *anyopaque, parser: *zparser.Parser) zparser.ParseError!zparser.FunctionHookResult {
    const self = selfFromCtx(ctx);
    const cnode = self.parseClass(parser, false) catch |err| {
        self.last_error = err;
        return zparser.ParseError.UnexpectedToken;
    };
    return .{ .node = cnode, .end = cnode.end };
}

fn classDeclarationHook(ctx: *anyopaque, parser: *zparser.Parser) zstatements.ParseError!zstatements.StatementHookResult {
    const self = selfFromCtx(ctx);
    const cnode = self.parseClass(parser, true) catch |err| {
        self.last_error = err;
        return zstatements.ParseError.UnexpectedToken;
    };
    return .{ .node = cnode, .end = cnode.end };
}

fn functionDeclarationHook(ctx: *anyopaque, parser: *zparser.Parser) zstatements.ParseError!zstatements.StatementHookResult {
    const self = selfFromCtx(ctx);
    const start = parser.current.start;
    const flags = parseFunctionFlags(parser) catch |err| {
        self.last_error = err;
        return zstatements.ParseError.UnexpectedToken;
    };
    if (parser.current.type != .identifier) {
        self.last_error = ParseError.MissingFunctionName;
        return zstatements.ParseError.UnexpectedToken;
    }
    const binding = try self.stmt_parser.parseBindingName(); // zstatements-typed already, try normal
    const saved = setBodyFlags(parser, false, false);
    defer {
        parser.yield_allowed = saved.y;
        parser.await_allowed = saved.a;
    }
    const params = self.parseParams(parser) catch |err| {
        self.last_error = err;
        return zstatements.ParseError.UnexpectedToken;
    };
    parser.yield_allowed = flags.is_generator;
    parser.await_allowed = flags.is_async;
    const body_stmt = try self.stmt_parser.parseBlockStatement(); // zstatements-typed already, try normal
    const node = try self.arena.create(ast.FunctionNode);
    node.* = .{
        .start = start,
        .end = body_stmt.end,
        .kind = .{ .function_decl = .{ .name = binding.name } },
        .params = params,
        .body = .{ .block = body_stmt },
        .is_generator = flags.is_generator,
        .is_async = flags.is_async,
    };
    return .{ .node = node, .end = node.end };
}
