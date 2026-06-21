const std = @import("std");

pub fn build(b: *std.Build) void {
    // Manuelle Query für Musl-Linux vorbereiten
    const query = std.Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
    };

    // In Zig 0.16.0 direkt auf dem 'b' (std.Build) aufzurufen
    const target = b.resolveTargetQuery(query);
    const optimize = b.standardOptimizeOption(.{});

    // --- 1. sipctl Executable ---
    const sipctl_mod = b.createModule(.{
        .root_source_file = b.path("src/sipctl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    sipctl_mod.addCSourceFile(.{
        .file = b.path("src/time.c"),
        .flags = &.{"-std=c11"},
    });

    const sipctl = b.addExecutable(.{
        .name = "sipctl",
        .root_module = sipctl_mod,
    });
    b.installArtifact(sipctl);

    // --- 2. server_cli Executable ---
    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/server_cli.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    server_mod.addCSourceFile(.{
        .file = b.path("src/time.c"),
        .flags = &.{"-std=c11"},
    });

    const server_cli = b.addExecutable(.{
        .name = "server_cli",
        .root_module = server_mod,
    });
    b.installArtifact(server_cli);

    // --- Run Steps ---
    const run_sipctl = b.addRunArtifact(sipctl);
    run_sipctl.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_sipctl.addArgs(args);
    const run_sipctl_step = b.step("run-sipctl", "Run sipctl");
    run_sipctl_step.dependOn(&run_sipctl.step);

    const run_server = b.addRunArtifact(server_cli);
    run_server.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_server.addArgs(args);
    const run_server_step = b.step("run-server", "Run server_cli");
    run_server_step.dependOn(&run_server.step);
}
