const zparser = @import("zparser");
const zstatements = @import("zstatements");

/// A binding parameter and its optional default expression.
pub const Param = struct {
    /// Identifier or destructuring pattern (`function f([a, b], {x}) ...`).
    pattern: *zstatements.BindingPattern,
    default: ?*zparser.Node,
};

/// Identifier or destructuring pattern (`function f(...[a, b]) ...`,
/// `function f(...{x}) ...`) -- same grammar production as `Param.pattern`
/// above (BindingPattern already covers the plain-identifier case as its
/// `.identifier` variant). Rest never has a default.
pub const RestParam = *zstatements.BindingPattern;

/// Regular parameters in source order and an optional trailing rest binding.
pub const Params = struct {
    items: []const Param,
    rest: ?RestParam,
};

/// A block body or an arrow function's implicitly returned expression.
pub const FunctionBody = union(enum) {
    block: *zstatements.Statement, // always a `.block`-kind Statement
    /// Arrow "concise body": a single AssignmentExpression, implicitly
    /// returned. Only arrows can have this form.
    expression: *zparser.Node,
};

/// Function syntax category and any declared name.
pub const FunctionKind = union(enum) {
    function_decl: struct { name: []const u8 }, // always required
    function_expr: struct { name: ?[]const u8 }, // anonymous is legal
    arrow: void, // arrows are never named
    /// Object-literal method / getter / setter body. `name` is the
    /// property key's source text ("" for computed keys). Methods are not
    /// constructors and never self-bind their name.
    method: struct { name: []const u8 },
};

/// Arena-owned function syntax; `start` and `end` are byte offsets in the source.
pub const FunctionNode = struct {
    start: usize,
    end: usize,
    kind: FunctionKind,
    params: Params,
    body: FunctionBody,
    /// `function* f()` -- calling it builds a generator object instead of
    /// running the body; `yield` is grammatical inside.
    is_generator: bool = false,
    /// `async function f()` -- calling it returns a promise; `await` is
    /// grammatical inside. Both flags set = `async function*` (parses;
    /// the interpreter rejects async generators at runtime for now).
    is_async: bool = false,
};

/// Recovers a typed FunctionNode from the opaque pointer stored in either
/// `zparser.NodeData.function_like` or `zstatements.StatementData.function_declaration`.
pub fn asFunctionNode(ptr: *anyopaque) *FunctionNode {
    return @ptrCast(@alignCast(ptr));
}

/// The syntactic category of a class member.
pub const ClassElementKind = enum { method, get, set, field, static_block };

/// A class element's property key. Numeric keys are pre-formatted to their
/// string form at parse time (they're ordinary string keys at runtime).
pub const ClassKey = union(enum) {
    /// Identifier / keyword / string-literal / numeric key.
    ident: []const u8,
    /// A `#name` private key, stored WITH the leading '#' (matching the
    /// lexer's `.private_identifier` lexeme) so it can never collide with
    /// an ordinary identifier key.
    private: []const u8,
    /// `[expr]` -- evaluated once, in declaration order, during
    /// ClassDefinitionEvaluation (the interpreter's job).
    computed: *zparser.Node,
};

/// A class member with a key and either a function body or field initializer.
pub const ClassElement = struct {
    kind: ClassElementKind,
    /// For `.static_block` this is `.{ .ident = "" }` (blocks are keyless).
    key: ClassKey,
    is_static: bool,
    /// Methods/accessors and static blocks carry their body here (always a
    /// `.method`-kind FunctionNode; a static block is a synthetic
    /// parameterless one). Null for fields.
    function: ?*FunctionNode,
    /// A field's initializer expression; null = no initializer (undefined).
    /// Always null for methods/accessors/static blocks.
    value: ?*zparser.Node = null,
};

/// Arena-owned class syntax; `start` and `end` are byte offsets in the source.
pub const ClassNode = struct {
    start: usize,
    end: usize,
    /// null only for anonymous class *expressions*; declarations require
    /// a name (MissingClassName).
    name: ?[]const u8,
    /// Arbitrary LeftHandSideExpression after `extends` (`class B extends
    /// mixin(A)` is legal); runtime demands a constructable function.
    superclass: ?*zparser.Node,
    elements: []const ClassElement,
};

/// Recovers a typed ClassNode from the opaque pointer stored in either
/// `zparser.NodeData.class_like` or `zstatements.StatementData.class_declaration`.
pub fn asClassNode(ptr: *anyopaque) *ClassNode {
    return @ptrCast(@alignCast(ptr));
}

/// Returns the exclusive source end offset of a block or expression body.
pub fn functionBodyEnd(body: FunctionBody) usize {
    return switch (body) {
        .block => |b| b.end,
        .expression => |e| e.end,
    };
}
