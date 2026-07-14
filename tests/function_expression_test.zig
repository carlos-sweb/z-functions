const std = @import("std");
const testing = std.testing;
const zfunctions = @import("zfunctions");
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "anonymous function expression" {
    try helpers.parseExprAndCheck("(function () { return 1; })", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .paren);
            const inner = node.data.paren;
            try testing.expect(inner.data == .function_like);
            const fnode = zfunctions.asFunctionNode(inner.data.function_like);
            try testing.expect(fnode.kind == .function_expr);
            try testing.expect(fnode.kind.function_expr.name == null);
        }
    }.check);
}

test "named function expression stores its name" {
    try helpers.parseExprAndCheck("(function fact(n) { return fact(n); })", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const inner = node.data.paren;
            const fnode = zfunctions.asFunctionNode(inner.data.function_like);
            try testing.expect(fnode.kind.function_expr.name != null);
            try testing.expectEqualStrings("fact", fnode.kind.function_expr.name.?);
        }
    }.check);
}

test "IIFE: call right after a function expression" {
    try helpers.parseExprAndCheck("(function(){ return 1; })()", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call);
            try testing.expect(node.data.call.callee.data == .paren);
            try testing.expect(node.data.call.callee.data.paren.data == .function_like);
        }
    }.check);
}
