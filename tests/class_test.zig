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
            try testing.expectEqualStrings("constructor", cnode.elements[0].key.ident);
            try testing.expect(cnode.elements[0].kind == .method);
            try testing.expect(!cnode.elements[0].is_static);
            try testing.expect(cnode.elements[2].kind == .get);
            try testing.expect(cnode.elements[3].kind == .set);
            try testing.expect(cnode.elements[4].is_static);
            try testing.expect(cnode.elements[5].is_static);
            try testing.expect(cnode.elements[5].kind == .get);
            // Every element body is a .method-kind FunctionNode.
            try testing.expect(cnode.elements[1].function.?.kind == .method);
            try testing.expectEqualStrings("m", cnode.elements[1].function.?.kind.method.name);
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
            try testing.expectEqualStrings("static", cnode.elements[0].key.ident);
            try testing.expect(!cnode.elements[0].is_static);
            try testing.expectEqualStrings("get", cnode.elements[1].key.ident);
            try testing.expect(cnode.elements[1].kind == .method);
        }
    }.check);
}

test "semicolons between elements are tolerated; keyword keys parse" {
    try helpers.parseExprAndCheck("(class { m() {} ; delete() {} ; })", {}, struct {
        fn check(_: void, node: *zparser.Node) !void {
            const cnode = zfunctions.asClassNode(node.data.paren.data.class_like);
            try testing.expectEqual(@as(usize, 2), cnode.elements.len);
            try testing.expectEqualStrings("delete", cnode.elements[1].key.ident);
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

test "generator and async class methods carry the flags; async constructor is rejected" {
    try helpers.parseAndCheck("class C { *m() {} async a() {} static async *sg() {} }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const cnode = zfunctions.asClassNode(stmt.data.class_declaration);
            try testing.expect(cnode.elements[0].function.?.is_generator);
            try testing.expect(cnode.elements[1].function.?.is_async);
            try testing.expect(cnode.elements[2].is_static and cnode.elements[2].function.?.is_generator and cnode.elements[2].function.?.is_async);
        }
    }.check);
    try helpers.expectParseError("class C { async constructor() {} }", zfunctions.ParseError.ConstructorCannotBeAccessor);
    try helpers.expectParseError("class C { *constructor() {} }", zfunctions.ParseError.ConstructorCannotBeAccessor);
}

test "class fields: with/without initializer, static, and modifier-named fields" {
    try helpers.parseAndCheck(
        \\class C {
        \\  x = 1;
        \\  y;
        \\  static z = 2;
        \\  static = 3;
        \\  get = 4;
        \\}
    , {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const cnode = zfunctions.asClassNode(stmt.data.class_declaration);
            try testing.expectEqual(@as(usize, 5), cnode.elements.len);
            try testing.expect(cnode.elements[0].kind == .field);
            try testing.expectEqualStrings("x", cnode.elements[0].key.ident);
            try testing.expect(cnode.elements[0].value != null);
            try testing.expect(cnode.elements[1].value == null);
            try testing.expect(cnode.elements[2].is_static);
            // `static = 3` / `get = 4` are FIELDS named "static"/"get".
            try testing.expectEqualStrings("static", cnode.elements[3].key.ident);
            try testing.expect(!cnode.elements[3].is_static);
            try testing.expectEqualStrings("get", cnode.elements[4].key.ident);
        }
    }.check);
}

test "private fields, methods, accessors, and static privates" {
    try helpers.parseAndCheck(
        \\class C {
        \\  #x = 1;
        \\  #m() { return this.#x; }
        \\  get #v() { return 2; }
        \\  static #count = 0;
        \\  static #tick() {}
        \\}
    , {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const cnode = zfunctions.asClassNode(stmt.data.class_declaration);
            try testing.expectEqual(@as(usize, 5), cnode.elements.len);
            try testing.expectEqualStrings("#x", cnode.elements[0].key.private);
            try testing.expect(cnode.elements[0].kind == .field);
            try testing.expectEqualStrings("#m", cnode.elements[1].key.private);
            try testing.expect(cnode.elements[1].kind == .method);
            try testing.expect(cnode.elements[2].kind == .get);
            try testing.expect(cnode.elements[3].is_static and cnode.elements[3].kind == .field);
            try testing.expect(cnode.elements[4].is_static and cnode.elements[4].kind == .method);
        }
    }.check);
}

test "computed and numeric keys" {
    try helpers.parseAndCheck(
        \\class C {
        \\  [Symbol.iterator]() {}
        \\  ["a" + "b"] = 1;
        \\  1() {}
        \\}
    , {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const cnode = zfunctions.asClassNode(stmt.data.class_declaration);
            try testing.expectEqual(@as(usize, 3), cnode.elements.len);
            try testing.expect(cnode.elements[0].key == .computed);
            try testing.expect(cnode.elements[1].key == .computed and cnode.elements[1].kind == .field);
            try testing.expectEqualStrings("1", cnode.elements[2].key.ident);
        }
    }.check);
}

test "static initialization blocks" {
    try helpers.parseAndCheck(
        \\class C {
        \\  static x = 1;
        \\  static { this.y = this.x + 1; }
        \\}
    , {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const cnode = zfunctions.asClassNode(stmt.data.class_declaration);
            try testing.expectEqual(@as(usize, 2), cnode.elements.len);
            try testing.expect(cnode.elements[1].kind == .static_block);
            try testing.expect(cnode.elements[1].is_static);
            try testing.expect(cnode.elements[1].function != null);
        }
    }.check);
}

test "field early errors: constructor-named fields and #constructor" {
    try helpers.expectParseError("class C { constructor = 1; }", zfunctions.ParseError.UnexpectedToken);
    try helpers.expectParseError("class C { #constructor() {} }", zfunctions.ParseError.UnexpectedToken);
    try helpers.expectParseError("class C { get x = 1; }", zfunctions.ParseError.UnexpectedToken);
}
