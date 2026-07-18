//! Class declarations/expressions (ECMA-262 section 15.7, narrowed).
const std = @import("std");
const testing = std.testing;
const zfunctions = @import("zfunctions");
const zstatements = @import("zstatements");
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "class declaration: name, superclass, element kinds and staticness" {
    try helpers.parseAndCheck(
        \\class B extends A {
        \\  constructor(x) { this.x = x; }
        \\  m() { return 1; }
        \\  get v() { return 2; }
        \\  set v(x) { x; }
        \\  static make() { return 3; }
        \\  static get tag() { return 4; }
        \\}
    , {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .class_declaration);
            const cnode = zfunctions.asClassNode(stmt.data.class_declaration);
            try testing.expectEqualStrings("B", cnode.name.?);
            try testing.expect(cnode.superclass != null);
            try testing.expectEqualStrings("A", cnode.superclass.?.data.identifier);
            try testing.expectEqual(@as(usize, 6), cnode.elements.len);
            try testing.expectEqualStrings("constructor", cnode.elements[0].key);
            try testing.expect(cnode.elements[0].kind == .method);
            try testing.expect(!cnode.elements[0].is_static);
            try testing.expect(cnode.elements[2].kind == .get);
            try testing.expect(cnode.elements[3].kind == .set);
            try testing.expect(cnode.elements[4].is_static);
            try testing.expect(cnode.elements[5].is_static);
            try testing.expect(cnode.elements[5].kind == .get);
            // Every element body is a .method-kind FunctionNode.
            try testing.expect(cnode.elements[1].function.kind == .method);
            try testing.expectEqualStrings("m", cnode.elements[1].function.kind.method.name);
        }
    }.check);
}

test "class expression: anonymous, and methods named static/get/set stay methods" {
    try helpers.parseExprAndCheck("(class { static() { return 1; } get() { return 2; } })", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const cnode = zfunctions.asClassNode(node.data.paren.data.class_like);
            try testing.expect(cnode.name == null);
            try testing.expect(cnode.superclass == null);
            try testing.expectEqual(@as(usize, 2), cnode.elements.len);
            try testing.expectEqualStrings("static", cnode.elements[0].key);
            try testing.expect(!cnode.elements[0].is_static);
            try testing.expectEqualStrings("get", cnode.elements[1].key);
            try testing.expect(cnode.elements[1].kind == .method);
        }
    }.check);
}

test "semicolons between elements are tolerated; keyword keys parse" {
    try helpers.parseExprAndCheck("(class { m() {} ; delete() {} ; })", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const cnode = zfunctions.asClassNode(node.data.paren.data.class_like);
            try testing.expectEqual(@as(usize, 2), cnode.elements.len);
            try testing.expectEqualStrings("delete", cnode.elements[1].key);
        }
    }.check);
}

test "class-body early errors" {
    try helpers.expectParseError("class {}", zfunctions.ParseError.MissingClassName);
    try helpers.expectParseError("class X { constructor() {} constructor() {} }", zfunctions.ParseError.DuplicateConstructor);
    try helpers.expectParseError("class X { get constructor() {} }", zfunctions.ParseError.ConstructorCannotBeAccessor);
    try helpers.expectParseError("class X { get a(b) {} }", zfunctions.ParseError.GetterCannotHaveParameters);
    try helpers.expectParseError("class X { set a() {} }", zfunctions.ParseError.SetterMustHaveExactlyOneParameter);
}

test "a static method named constructor is legal" {
    try helpers.parseAndCheck("class X { static constructor() {} constructor() {} }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const cnode = zfunctions.asClassNode(stmt.data.class_declaration);
            try testing.expectEqual(@as(usize, 2), cnode.elements.len);
        }
    }.check);
}
