const std = @import("std");
const testing = std.testing;
const zfunctions = @import("zfunctions");
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "named function declaration produces .function_declaration, not .expr_stmt" {
    try helpers.parseAndCheck("function foo(a, b) { return a + b; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .function_declaration);
            const fnode = zfunctions.asFunctionNode(stmt.data.function_declaration);
            try testing.expect(fnode.kind == .function_decl);
            try testing.expectEqualStrings("foo", fnode.kind.function_decl.name);
            try testing.expectEqual(@as(usize, 2), fnode.params.items.len);
            try testing.expect(fnode.body == .block);
        }
    }.check);
}

test "function declaration with no name is a hard error" {
    try helpers.expectParseError("function () {}", zfunctions.ParseError.MissingFunctionName);
}

test "a declaration's body is a full StatementList" {
    try helpers.parseAndCheck("function f() { var x = 1; if (x) { return x; } }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const fnode = zfunctions.asFunctionNode(stmt.data.function_declaration);
            try testing.expect(fnode.body.block.data == .block);
            try testing.expectEqual(@as(usize, 2), fnode.body.block.data.block.len);
        }
    }.check);
}

test "recursive named declaration parses (no scope/binding semantics needed)" {
    try helpers.parseAndCheck("function fact(n) { return n <= 1 ? 1 : n * fact(n - 1); }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .function_declaration);
        }
    }.check);
}
