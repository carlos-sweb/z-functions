//! Object-literal method / getter / setter shorthand, parsed through the
//! full z-functions parser (z-parser's parseMethod hook + this repo's
//! params/body grammar and arity validation).
const std = @import("std");
const testing = std.testing;
const zfunctions = @import("zfunctions");
const zstatements = @import("zstatements");
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "method shorthand parses with kind .method and the key as its name" {
    try helpers.parseExprAndCheck("({m(a, b) { return a; }})", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const els = node.data.paren.data.object_literal;
            const prop = els[0].property;
            try testing.expect(prop.kind == .method);
            const fnode = zfunctions.asFunctionNode(prop.value.data.function_like);
            try testing.expect(fnode.kind == .method);
            try testing.expectEqualStrings("m", fnode.kind.method.name);
            try testing.expectEqual(@as(usize, 2), fnode.params.items.len);
        }
    }.check);
}

test "getter and setter clauses parse with their kinds" {
    try helpers.parseExprAndCheck("({get x() { return 1; }, set x(v) { v; }})", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const els = node.data.paren.data.object_literal;
            try testing.expect(els[0].property.kind == .get);
            try testing.expectEqualStrings("x", els[0].property.key.data.identifier);
            try testing.expect(els[1].property.kind == .set);
            const setter = zfunctions.asFunctionNode(els[1].property.value.data.function_like);
            try testing.expectEqual(@as(usize, 1), setter.params.items.len);
        }
    }.check);
}

test "computed and keyword method keys parse" {
    try helpers.parseExprAndCheck("({[k]() {}, if() {}})", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const els = node.data.paren.data.object_literal;
            try testing.expect(els[0].property.computed);
            try testing.expect(els[0].property.kind == .method);
            try testing.expectEqualStrings("if", els[1].property.key.data.identifier);
        }
    }.check);
}

test "a method named get/set still parses as a method" {
    try helpers.parseExprAndCheck("({get() { return 2; }})", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const prop = node.data.paren.data.object_literal[0].property;
            try testing.expect(prop.kind == .method);
            try testing.expectEqualStrings("get", prop.key.data.identifier);
        }
    }.check);
}

test "accessor arity is validated with precise errors" {
    try helpers.expectParseError("({get x(a) {}});", zfunctions.ParseError.GetterCannotHaveParameters);
    try helpers.expectParseError("({set x() {}});", zfunctions.ParseError.SetterMustHaveExactlyOneParameter);
    try helpers.expectParseError("({set x(a, b) {}});", zfunctions.ParseError.SetterMustHaveExactlyOneParameter);
    try helpers.expectParseError("({set x(...a) {}});", zfunctions.ParseError.SetterMustHaveExactlyOneParameter);
}

test "methods are invalid destructuring assignment targets" {
    try helpers.expectParseError("({ m() {} } = x);", zfunctions.ParseError.InvalidAssignmentTarget);
}
