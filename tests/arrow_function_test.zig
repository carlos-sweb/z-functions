const std = @import("std");
const testing = std.testing;
const zfunctions = @import("zfunctions");
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

fn arrowOf(node: *zparser.Node) *zfunctions.FunctionNode {
    return zfunctions.asFunctionNode(node.data.function_like);
}

test "bare identifier arrow, no parens" {
    try helpers.parseExprAndCheck("a => a + 1", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .function_like);
            const fnode = arrowOf(node);
            try testing.expect(fnode.kind == .arrow);
            try testing.expectEqual(@as(usize, 1), fnode.params.items.len);
            try testing.expectEqualStrings("a", fnode.params.items[0].pattern.identifier.name);
            try testing.expect(fnode.body == .expression);
        }
    }.check);
}

test "zero-parameter arrow" {
    try helpers.parseExprAndCheck("() => 1", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = arrowOf(node);
            try testing.expectEqual(@as(usize, 0), fnode.params.items.len);
            try testing.expect(fnode.params.rest == null);
        }
    }.check);
}

test "multi-parameter arrow with block body" {
    try helpers.parseExprAndCheck("(a, b) => { return a + b; }", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = arrowOf(node);
            try testing.expectEqual(@as(usize, 2), fnode.params.items.len);
            try testing.expect(fnode.body == .block);
        }
    }.check);
}

test "rest-only arrow" {
    try helpers.parseExprAndCheck("(...args) => args", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = arrowOf(node);
            try testing.expectEqual(@as(usize, 0), fnode.params.items.len);
            try testing.expect(fnode.params.rest != null);
            try testing.expectEqualStrings("args", fnode.params.rest.?.name);
        }
    }.check);
}

test "concise body returning a parenthesized object literal" {
    try helpers.parseExprAndCheck("x => ({ a: 1 })", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = arrowOf(node);
            try testing.expect(fnode.body == .expression);
            try testing.expect(fnode.body.expression.data == .paren);
            try testing.expect(fnode.body.expression.data.paren.data == .object_literal);
        }
    }.check);
}

test "a bare '{' after '=>' is always a block, not an object literal (classic gotcha)" {
    try helpers.parseExprAndCheck("x => { a: 1 }", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = arrowOf(node);
            try testing.expect(fnode.body == .block);
            const block = fnode.body.block;
            try testing.expectEqual(@as(usize, 1), block.data.block.len);
            try testing.expect(block.data.block[0].data == .labelled);
        }
    }.check);
}

test "a plain parenthesized expression not followed by '=>' stays .paren/.sequence" {
    try helpers.parseExprAndCheck("(a + b)", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .paren);
            try testing.expect(node.data.paren.data == .binary);
        }
    }.check);
    try helpers.parseExprAndCheck("(a, b)", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .paren);
            try testing.expect(node.data.paren.data == .sequence);
        }
    }.check);
}

test "arrow nested mid-expression as a call argument" {
    try helpers.parseExprAndCheck("f(() => 1, x + 1)", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            try testing.expect(node.data == .call);
            const args = node.data.call.args;
            try testing.expectEqual(@as(usize, 2), args.len);
            try testing.expect(args[0].data == .function_like);
            try testing.expect(args[1].data == .binary);
        }
    }.check);
}
