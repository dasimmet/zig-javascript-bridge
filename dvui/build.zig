const std = @import("std");

// For export to users who are bringing their own backend.  Use in your build.zig:
// const dvui_mod = dvui_dep.module("dvui");
// @import("dvui").linkBackend(dvui_mod, your backend module);

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const simple = b.addExecutable(.{
        .name = "simple",
        .root_source_file = b.path("src/simple.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple.entry = .disabled;
    simple.rdynamic = true;

    const zjb = b.dependency("javascript_bridge", .{
        .wasm_bindgen_bin = simple.getEmittedBin(),
    });
    const zjb_mod = zjb.module("zjb");

    const dvui_mod = b.dependency("dvui", .{
        .optimize = optimize,
    }).module("dvui_web");

    const dvui_zjb_backend = b.createModule(.{
        .root_source_file = b.path("src/dvui_backend.zig"),
    });
    dvui_zjb_backend.addImport("zjb", zjb_mod);
    @import("dvui").linkBackend(dvui_mod, dvui_zjb_backend);
    simple.root_module.addImport("dvui", dvui_mod);

    const extract_simple_out = zjb.namedLazyPath("zjb_extract.js");

    simple.root_module.addImport("zjb", zjb_mod);

    const simple_step = b.step("simple", "Build the hello Zig example");
    simple_step.dependOn(&b.addInstallArtifact(simple, .{
        .dest_dir = .{ .override = dir },
    }).step);
    simple_step.dependOn(&b.addInstallFileWithDir(extract_simple_out, dir, "zjb_extract.js").step);
    simple_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);
}
