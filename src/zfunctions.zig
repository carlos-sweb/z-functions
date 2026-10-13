//! ECMAScript function, arrow function, method, and class parsing.
//!
//! Create `Parser` with an arena allocator and source text, then call
//! `Parser.parseProgram`, `Parser.parseStatement`, or `Parser.parseExpression`.
//! Keep the arena and source alive while using the returned syntax tree.
//! Function and class nodes extend z-parser and z-statements through opaque
//! pointers; recover them with `asFunctionNode` and `asClassNode`.

const ast_mod = @import("ast.zig");
const parser_mod = @import("parser.zig");

/// A regular parameter with an optional default expression.
pub const Param = ast_mod.Param;
/// A rest parameter's binding pattern.
pub const RestParam = ast_mod.RestParam;
/// Ordered parameters and an optional trailing rest parameter.
pub const Params = ast_mod.Params;
/// A statement block or an arrow function's concise expression body.
pub const FunctionBody = ast_mod.FunctionBody;
/// Distinguishes declarations, expressions, arrows, and methods.
pub const FunctionKind = ast_mod.FunctionKind;
/// A function's source span, parameters, body, and async/generator flags.
pub const FunctionNode = ast_mod.FunctionNode;
/// Recovers a function node from a function hook's opaque pointer.
pub const asFunctionNode = ast_mod.asFunctionNode;
/// Distinguishes methods, accessors, fields, and static blocks.
pub const ClassElementKind = ast_mod.ClassElementKind;
/// A class member, including its key, modifiers, and body or initializer.
pub const ClassElement = ast_mod.ClassElement;
/// A class's source span, name, superclass, and members.
pub const ClassNode = ast_mod.ClassNode;
/// Recovers a class node from a class hook's opaque pointer.
pub const asClassNode = ast_mod.asClassNode;

/// Parser whose function and class hooks share a stable arena-allocated context.
pub const Parser = parser_mod.Parser;
/// Lexical, expression, statement, and function/class parsing failures.
pub const ParseError = parser_mod.ParseError;

test {
    _ = @import("ast.zig");
    _ = @import("parser.zig");
}
