const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fetch_mod = b.createModule(.{
        .root_source_file = b.path("src/fetch.zig"),
        .target           = target,
        .optimize         = optimize,
    });

    const exe = b.addExecutable(.{
        .name        = "cachyfetch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target           = target,
            .optimize         = optimize,
            .imports          = &.{
                .{ .name = "fetch", .module = fetch_mod },
            },
        }),
    });
    exe.root_module.strip = optimize != .Debug;
    b.installArtifact(exe);

    const run_cmd  = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    b.step("run", "Run cachyfetch").dependOn(&run_cmd.step);
}
