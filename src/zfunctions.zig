const ast_mod = @import("ast.zig");
const parser_mod = @import("parser.zig");

pub const Param = ast_mod.Param;
pub const RestParam = ast_mod.RestParam;
pub const Params = ast_mod.Params;
pub const FunctionBody = ast_mod.FunctionBody;
pub const FunctionKind = ast_mod.FunctionKind;
pub const FunctionNode = ast_mod.FunctionNode;
pub const asFunctionNode = ast_mod.asFunctionNode;

pub const Parser = parser_mod.Parser;
pub const ParseError = parser_mod.ParseError;

test {
    _ = @import("ast.zig");
    _ = @import("parser.zig");
}
