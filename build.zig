const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlexer_dep = b.dependency("zlexer", .{ .target = target, .optimize = optimize });
    const zlexer_module = zlexer_dep.module("zlexer");

    const zstatements_dep = b.dependency("zstatements", .{ .target = target, .optimize = optimize });
    const zstatements_module = zstatements_dep.module("zstatements");
    // Reuse the bundled parser so all hooks share the same AST types.
    const zparser_module = zstatements_module.import_table.get("zparser").?;
    // Use the pinned Zig 0.17 lexer throughout the dependency graph.
    zparser_module.addImport("zlexer", zlexer_module);
    zstatements_module.addImport("zlexer", zlexer_module);

    const zfunctions_module = b.addModule("zfunctions", .{
        .root_source_file = b.path("src/zfunctions.zig"),
        .target = target,
        .optimize = optimize,
    });
    zfunctions_module.addImport("zlexer", zlexer_module);
    zfunctions_module.addImport("zparser", zparser_module);
    zfunctions_module.addImport("zstatements", zstatements_module);

    const docs_object = b.addObject(.{
        .name = "zfunctions",
        .root_module = zfunctions_module,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_object.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate the official Zig API documentation");
    docs_step.dependOn(&install_docs.step);

    const test_step = b.step("test", "Run all tests");

    const test_files = [_][]const u8{
        "tests/function_declaration_test.zig",
        "tests/function_expression_test.zig",
        "tests/arrow_function_test.zig",
        "tests/parameters_test.zig",
        "tests/method_test.zig",
        "tests/class_test.zig",
        "tests/integration_test.zig",
    };

    inline for (test_files) |test_file| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
            }),
        });

        unit_tests.root_module.addImport("zfunctions", zfunctions_module);
        unit_tests.root_module.addImport("zparser", zparser_module);
        unit_tests.root_module.addImport("zstatements", zstatements_module);

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    const src_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zfunctions.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    src_tests.root_module.addImport("zparser", zparser_module);
    src_tests.root_module.addImport("zlexer", zlexer_module);
    src_tests.root_module.addImport("zstatements", zstatements_module);
    const run_src_tests = b.addRunArtifact(src_tests);
    test_step.dependOn(&run_src_tests.step);

    b.default_step = test_step;
}
