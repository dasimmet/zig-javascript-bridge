const std = @import("std");

// For export to users who are bringing their own backend.  Use in your build.zig:
// const dvui_mod = dvui_dep.module("dvui");
// @import("dvui").linkBackend(dvui_mod, your backend module);

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const dir = std.Build.InstallDir.bin;

    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const dvui_example = b.addExecutable(.{
        .name = "dvui",
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    dvui_example.entry = .disabled;
    dvui_example.rdynamic = true;

    const zjb = b.dependency("javascript_bridge", .{
        .wasm_bindgen_bin = dvui_example.getEmittedBin(),
    });
    const zjb_mod = zjb.module("zjb");
    const extract_out = zjb.namedLazyPath("zjb_extract.js");

    const dvui_mod = b.dependency("dvui", .{
        .optimize = optimize,
        .target = target,
        .disable_backends = true,
    }).module("dvui");

    const dvui_zjb_backend = b.createModule(.{
        .root_source_file = b.path("src/dvui_zjb_backend.zig"),
    });
    dvui_zjb_backend.addImport("zjb", zjb_mod);
    @import("dvui").linkBackend(dvui_mod, dvui_zjb_backend);
    dvui_example.root_module.addImport("dvui", dvui_mod);

    dvui_example.root_module.addImport("zjb", zjb_mod);

    const dvui_step = b.step("dvui", "Build the hello Zig example");
    dvui_step.dependOn(&b.addInstallArtifact(dvui_example, .{
        .dest_dir = .{ .override = dir },
    }).step);
    dvui_step.dependOn(&b.addInstallFileWithDir(extract_out, dir, "zjb_extract.js").step);
    dvui_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);
    b.default_step.dependOn(dvui_step);
}
