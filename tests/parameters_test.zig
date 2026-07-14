const std = @import("std");
const testing = std.testing;
const zfunctions = @import("zfunctions");
const zstatements = @import("zstatements");
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "a default value can reference an earlier parameter (no scope analysis here)" {
    try helpers.parseExprAndCheck("(a, b = a + 1) => a + b", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = zfunctions.asFunctionNode(node.data.function_like);
            try testing.expect(fnode.params.items[1].default != null);
            try testing.expect(fnode.params.items[1].default.?.data == .binary);
        }
    }.check);
}

test "trailing comma after regular params is accepted" {
    try helpers.parseExprAndCheck("(a, b,) => a + b", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = zfunctions.asFunctionNode(node.data.function_like);
            try testing.expectEqual(@as(usize, 2), fnode.params.items.len);
        }
    }.check);
}

test "rest parameter must be last -- a param after it" {
    try helpers.expectParseError("f = (...a, b) => a;", zfunctions.ParseError.RestParameterMustBeLast);
}

test "rest parameter must be last -- a default value on it" {
    try helpers.expectParseError("f = (...a = 1) => a;", zfunctions.ParseError.RestParameterMustBeLast);
}

test "rest parameter must be last -- a trailing comma after it" {
    try helpers.expectParseError("f = (a, ...b,) => a;", zfunctions.ParseError.RestParameterMustBeLast);
}

test "destructuring parameters are rejected, reusing zstatements' error" {
    try helpers.expectParseError("function f([a]) {}", zstatements.ParseError.DestructuringBindingNotSupported);
    try helpers.expectParseError("f = (a, {b}) => a;", zstatements.ParseError.DestructuringBindingNotSupported);
}
