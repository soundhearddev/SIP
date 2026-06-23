const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protocol_mod = b.createModule(.{ .root_source_file = b.path("src/protocol.zig") });
    const sip_mod = b.createModule(.{ .root_source_file = b.path("src/sip.zig") });
    const synet_mod = b.createModule(.{ .root_source_file = b.path("src/synet.zig") });
    const fragmentation_mod = b.createModule(.{ .root_source_file = b.path("src/fragmentation.zig") });
    const header_mod = b.createModule(.{ .root_source_file = b.path("src/header.zig") });
    header_mod.addImport("protocol", protocol_mod);
    const translation_mod = b.createModule(.{ .root_source_file = b.path("src/translation.zig") });
    translation_mod.addImport("header", header_mod);

    const sipctl_mod = b.createModule(.{
        .root_source_file = b.path("src/usage/sipctl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sipctl_mod.addImport("protocol", protocol_mod);
    sipctl_mod.addImport("sip", sip_mod);
    sipctl_mod.addImport("header", header_mod);
    sipctl_mod.addImport("synet", synet_mod);
    sipctl_mod.addImport("translation", translation_mod);
    sipctl_mod.addImport("fragmentation", fragmentation_mod);
    const sipctl = b.addExecutable(.{ .name = "sipctl", .root_module = sipctl_mod });
    b.installArtifact(sipctl);

    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/usage/svr_clt_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    server_mod.addCSourceFile(.{
        .file = b.path("src/usage/time.c"),
        .flags = &.{"-std=c11"},
    });
    server_mod.addImport("protocol", protocol_mod);
    server_mod.addImport("sip", sip_mod);
    server_mod.addImport("header", header_mod);
    server_mod.addImport("synet", synet_mod);
    server_mod.addImport("translation", translation_mod);
    server_mod.addImport("fragmentation", fragmentation_mod);
    const server = b.addExecutable(.{ .name = "server_test", .root_module = server_mod });
    b.installArtifact(server);

    const header_test_mod = b.createModule(.{
        .root_source_file = b.path("src/usage/header_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const discover_mod = b.createModule(.{
        .root_source_file = b.path("src/usage/discoverer.zig"),
        .target = target,
        .optimize = optimize,
    });
    discover_mod.addImport("protocol", protocol_mod);
    const sniffer = b.addExecutable(.{ .name = "sniffer", .root_module = discover_mod });
    b.installArtifact(sniffer);
    const run_sniffer = b.addRunArtifact(sniffer);
    run_sniffer.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_sniffer.addArgs(args);
    b.step("run-sniffer", "Run sniffer").dependOn(&run_sniffer.step);

    header_test_mod.addImport("synet", synet_mod);
    header_test_mod.addImport("header", header_mod);
    header_test_mod.addImport("protocol", protocol_mod);
    const header_test = b.addExecutable(.{ .name = "header_test", .root_module = header_test_mod });
    b.installArtifact(header_test);

    const run_header_test = b.addRunArtifact(header_test);
    run_header_test.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_header_test.addArgs(args);
    b.step("run-header-test", "Run header_test").dependOn(&run_header_test.step);

    const run_sipctl = b.addRunArtifact(sipctl);
    run_sipctl.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_sipctl.addArgs(args);
    b.step("run-sipctl", "Run sipctl").dependOn(&run_sipctl.step);

    const run_server = b.addRunArtifact(server);
    run_server.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_server.addArgs(args);
    b.step("run-server", "Run server_test").dependOn(&run_server.step);
}
