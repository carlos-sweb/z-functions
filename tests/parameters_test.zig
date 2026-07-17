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

test "destructuring parameters parse as binding patterns" {
    try helpers.parseAndCheck("function f([a], {x = 1}) {}", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const fnode = zfunctions.asFunctionNode(stmt.data.function_declaration);
            try testing.expectEqual(@as(usize, 2), fnode.params.items.len);
            try testing.expect(fnode.params.items[0].pattern.* == .array);
            try testing.expectEqualStrings("a", fnode.params.items[0].pattern.array.elements[0].?.pattern.identifier.name);
            try testing.expect(fnode.params.items[1].pattern.* == .object);
            try testing.expect(fnode.params.items[1].pattern.object.properties[0].default != null);
        }
    }.check);
    try helpers.parseExprAndCheck("(a, {b}) => a", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = zfunctions.asFunctionNode(node.data.function_like);
            try testing.expect(fnode.params.items[0].pattern.* == .identifier);
            try testing.expect(fnode.params.items[1].pattern.* == .object);
        }
    }.check);
}

test "a destructuring param with a whole-param default parses (pattern default + param default combined)" {
    try helpers.parseExprAndCheck("({x = 1} = {}) => x", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const fnode = zfunctions.asFunctionNode(node.data.function_like);
            const param = fnode.params.items[0];
            try testing.expect(param.pattern.* == .object);
            try testing.expect(param.pattern.object.properties[0].default != null);
            try testing.expect(param.default != null);
        }
    }.check);
}
