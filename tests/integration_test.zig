const std = @import("std");
const testing = std.testing;
const zfunctions = @import("zfunctions");
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "a function expression nested deep inside another expression" {
    try helpers.parseExprAndCheck("f(() => 1, 1 + 2)", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call);
            try testing.expect(node.data.call.args[0].data == .function_like);
        }
    }.check);
}

test "IIFE end to end" {
    try helpers.parseExprAndCheck("(function(){ return 1; })()", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call);
        }
    }.check);
}

test "a ternary holding a function expression in one branch" {
    try helpers.parseExprAndCheck("a ? function(){} : b", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .conditional);
            try testing.expect(node.data.conditional.consequent.data == .function_like);
        }
    }.check);
}

test "curried arrows nest and right-associate naturally" {
    try helpers.parseExprAndCheck("a => b => a + b", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const outer = zfunctions.asFunctionNode(node.data.function_like);
            try testing.expect(outer.body == .expression);
            try testing.expect(outer.body.expression.data == .function_like);
            const inner = zfunctions.asFunctionNode(outer.body.expression.data.function_like);
            try testing.expectEqualStrings("b", inner.params.items[0].pattern.identifier.name);
        }
    }.check);
}
