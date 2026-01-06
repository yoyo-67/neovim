const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    // Force ReleaseFast for the library - no safety checks, no runtime symbols
    const optimize: std.builtin.OptimizeMode = .ReleaseFast;
    _ = b.standardOptimizeOption(.{}); // Still parse the option

    // Create the bidi library as a static library
    const lib = b.addLibrary(.{
        .name = "bidi",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bidi_lib.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true, // Strip debug info to remove runtime dependencies
            .omit_frame_pointer = true,
        }),
    });

    // Install the header for C consumers
    lib.installHeader(b.path("src/bidi.h"), "bidi.h");

    // Install the library
    b.installArtifact(lib);

    // Add test step
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bidi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
