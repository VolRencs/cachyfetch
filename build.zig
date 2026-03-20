const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name     = "cachyfetch",
        .target   = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("fetch", b.createModule(.{
        .root_source_file = b.path("src/fetch.zig"),
    }));
    exe.root_module.root_source_file = b.path("src/main.zig");
    exe.root_module.strip = optimize != .Debug;
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run cachyfetch");
    run_step.dependOn(&run_cmd.step);
}
