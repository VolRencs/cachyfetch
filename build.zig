const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name             = "cachyfetch",
        .root_source_file = b.path("src/main.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    exe.root_module.strip = optimize != .Debug;
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run cachyfetch");
    run_step.dependOn(&run_cmd.step);
}
