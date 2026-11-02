const std = @import("std");
const demo_webserver = @import("demo_webserver");
const javascript_bridge = @import("javascript_bridge");

const LazyPath = std.Build.LazyPath;

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
    const zjb = b.dependency("javascript_bridge", .{});
    const extract_example_out = javascript_bridge.bindgen(b, .{
        .basename = js_basename,
        .wasm = example.getEmittedBin(),
        .classname = "Zjb",
        .minify = b.option(bool, "minifyjs", "minify the js bindings") orelse false,
    });

    example.root_module.addImport("zjb", zjb.module("zjb"));

    const dir = std.Build.InstallDir.prefix;
    b.getInstallStep().dependOn(&b.addInstallArtifact(example, .{
        .dest_dir = .{ .override = dir },
    }).step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(extract_example_out, dir, js_basename).step);
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("static"),
        .install_dir = dir,
        .install_subdir = "",
    }).step);

    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(example.getEmittedBin(), b.fmt("{s}.wasm", .{example.name}));
    _ = wf.addCopyFile(extract_example_out, js_basename);
    _ = wf.addCopyDirectory(b.path("static"), "", .{});

    const run_demo_server = demo_webserver.runDemoServer(b, wf, .{});
    const serve = b.step("serve", "serve website locally");
    serve.dependOn(run_demo_server);
}
