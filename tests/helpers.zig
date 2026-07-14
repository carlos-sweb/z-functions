const std = @import("std");
const zfunctions = @import("zfunctions");
const zstatements = @import("zstatements");
const zparser = @import("zparser");

pub fn parseAndCheck(source: []const u8, context: anytype, comptime check: fn (@TypeOf(context), *zstatements.Statement) anyerror!void) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parser = try zfunctions.Parser.init(arena, source);
    const stmt = try parser.parseStatement();
    try check(context, stmt);
}

pub fn parseExprAndCheck(source: []const u8, context: anytype, comptime check: fn (@TypeOf(context), *zparser.Node) anyerror!void) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parser = try zfunctions.Parser.init(arena, source);
    const expr = try parser.parseExpression();
    try check(context, expr);
}

pub fn parseProgramAndCheck(source: []const u8, context: anytype, comptime check: fn (@TypeOf(context), []const *zstatements.Statement) anyerror!void) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parser = try zfunctions.Parser.init(arena, source);
    const program = try parser.parseProgram();
    try check(context, program);
}

pub fn expectParseError(source: []const u8, expected: zfunctions.ParseError) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parser = try zfunctions.Parser.init(arena, source);
    try std.testing.expectError(expected, parser.parseProgram());
}
