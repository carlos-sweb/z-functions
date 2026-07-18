const std = @import("std");
const Allocator = std.mem.Allocator;
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
        };
        self.stmt_parser.statement_hooks = .{
            .ctx = self,
            .parseFunctionDeclaration = functionDeclarationHook,
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
};

fn selfFromCtx(ctx: *anyopaque) *Parser {
    return @ptrCast(@alignCast(ctx));
}

fn arrowFunctionHook(ctx: *anyopaque, parser: *zparser.Parser) zparser.ParseError!zparser.FunctionHookResult {
    const self = selfFromCtx(ctx);
    const start = parser.current.start;
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
    const body = self.parseArrowBody(parser) catch |err| {
        self.last_error = err;
        return zparser.ParseError.UnexpectedToken;
    };
    const node = try self.arena.create(ast.FunctionNode);
    node.* = .{ .start = start, .end = ast.functionBodyEnd(body), .kind = .arrow, .params = params, .body = body };
    return .{ .node = node, .end = node.end };
}

fn functionExpressionHook(ctx: *anyopaque, parser: *zparser.Parser) zparser.ParseError!zparser.FunctionHookResult {
    const self = selfFromCtx(ctx);
    const start = parser.current.start;
    try parser.advance(); // 'function'
    var name: ?[]const u8 = null;
    if (parser.current.type == .identifier) {
        const binding = self.stmt_parser.parseBindingName() catch |err| {
            self.last_error = err;
            return zparser.ParseError.UnexpectedToken;
        };
        name = binding.name;
    }
    const params = self.parseParams(parser) catch |err| {
        self.last_error = err;
        return zparser.ParseError.UnexpectedToken;
    };
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
    };
    return .{ .node = node, .end = node.end };
}

fn methodHook(ctx: *anyopaque, parser: *zparser.Parser, kind: zparser.MethodKind, name: []const u8) zparser.ParseError!zparser.FunctionHookResult {
    const self = selfFromCtx(ctx);
    const start = parser.current.start;
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
    };
    return .{ .node = node, .end = node.end };
}

fn functionDeclarationHook(ctx: *anyopaque, parser: *zparser.Parser) zstatements.ParseError!zstatements.StatementHookResult {
    const self = selfFromCtx(ctx);
    const start = parser.current.start;
    try parser.advance(); // 'function'
    if (parser.current.type != .identifier) {
        self.last_error = ParseError.MissingFunctionName;
        return zstatements.ParseError.UnexpectedToken;
    }
    const binding = try self.stmt_parser.parseBindingName(); // zstatements-typed already, try normal
    const params = self.parseParams(parser) catch |err| {
        self.last_error = err;
        return zstatements.ParseError.UnexpectedToken;
    };
    const body_stmt = try self.stmt_parser.parseBlockStatement(); // zstatements-typed already, try normal
    const node = try self.arena.create(ast.FunctionNode);
    node.* = .{
        .start = start,
        .end = body_stmt.end,
        .kind = .{ .function_decl = .{ .name = binding.name } },
        .params = params,
        .body = .{ .block = body_stmt },
    };
    return .{ .node = node, .end = node.end };
}
