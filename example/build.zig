const std = @import("std");
const LazyPath = std.Build.LazyPath;
const demo_webserver = @import("demo_webserver");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = optimize,
        }),
    });
    example.entry = .disabled;
    example.rdynamic = true;

    const js_basename = "zjb_extract.js";
    const zjb = b.dependency("javascript_bridge", .{
        .wasm_bindgen_bin = example.getEmittedBin(),
        .wasm_bindgen_name = @as([]const u8, js_basename),
        .wasm_bindgen_classname = @as([]const u8, "Zjb"),
    });
    const extract_example_out = zjb.namedLazyPath(js_basename);

    example.root_module.addImport("zjb", zjb.module("zjb"));

    const dir = std.Build.InstallDir.prefix;
    b.getInstallStep().dependOn(&b.addInstallArtifact(example, .{
        .dest_dir = .{ .override = dir },
    }).step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(extract_example_out, dir, "zjb_extract.js").step);
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);

    const run_demo_server = demo_webserver.runDemoServer(b, b.getInstallStep(), .{});
    const serve = b.step("serve", "serve website locally");
    serve.dependOn(run_demo_server);
}
