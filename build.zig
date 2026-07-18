const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zparser_dep = b.dependency("zparser", .{ .target = target, .optimize = optimize });
    const zparser_module = zparser_dep.module("zparser");

    const zstatements_dep = b.dependency("zstatements", .{ .target = target, .optimize = optimize });
    const zstatements_module = zstatements_dep.module("zstatements");

    const zfunctions_module = b.addModule("zfunctions", .{
        .root_source_file = b.path("src/zfunctions.zig"),
    });
    zfunctions_module.addImport("zparser", zparser_module);
    zfunctions_module.addImport("zstatements", zstatements_module);

    const test_step = b.step("test", "Run all tests");

    const test_files = [_][]const u8{
        "tests/function_declaration_test.zig",
        "tests/function_expression_test.zig",
        "tests/arrow_function_test.zig",
        "tests/parameters_test.zig",
        "tests/method_test.zig",
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
    src_tests.root_module.addImport("zstatements", zstatements_module);
    const run_src_tests = b.addRunArtifact(src_tests);
    test_step.dependOn(&run_src_tests.step);

    b.default_step = test_step;
}
