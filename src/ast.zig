const zparser = @import("zparser");
const zstatements = @import("zstatements");

pub const Param = struct {
    /// Identifier or destructuring pattern (`function f([a, b], {x}) ...`).
    pattern: *zstatements.BindingPattern,
    default: ?*zparser.Node,
};

/// Identifier only (narrowed -- the real spec allows `...[a, b]` here too);
/// rest never has a default.
pub const RestParam = zstatements.BindingName;

pub const Params = struct {
    items: []const Param,
    rest: ?RestParam,
};

pub const FunctionBody = union(enum) {
    block: *zstatements.Statement, // always a `.block`-kind Statement
    /// Arrow "concise body": a single AssignmentExpression, implicitly
    /// returned. Only arrows can have this form.
    expression: *zparser.Node,
};

pub const FunctionKind = union(enum) {
    function_decl: struct { name: []const u8 }, // always required
    function_expr: struct { name: ?[]const u8 }, // anonymous is legal
    arrow: void, // arrows are never named
    /// Object-literal method / getter / setter body. `name` is the
    /// property key's source text ("" for computed keys). Methods are not
    /// constructors and never self-bind their name.
    method: struct { name: []const u8 },
};

pub const FunctionNode = struct {
    start: usize,
    end: usize,
    kind: FunctionKind,
    params: Params,
    body: FunctionBody,
};

/// Recovers a typed FunctionNode from the opaque pointer stored in either
/// `zparser.NodeData.function_like` or `zstatements.StatementData.function_declaration`.
pub fn asFunctionNode(ptr: *anyopaque) *FunctionNode {
    return @ptrCast(@alignCast(ptr));
}

pub const ClassElementKind = enum { method, get, set };

pub const ClassElement = struct {
    kind: ClassElementKind,
    /// Identifier/keyword/string keys only -- computed class-body keys
    /// are out of scope for this phase (object literals do have them).
    key: []const u8,
    is_static: bool,
    /// Always a `.method`-kind FunctionNode; the constructor is the
    /// non-static method element whose key is "constructor".
    function: *FunctionNode,
};

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

pub fn functionBodyEnd(body: FunctionBody) usize {
    return switch (body) {
        .block => |b| b.end,
        .expression => |e| e.end,
    };
}
