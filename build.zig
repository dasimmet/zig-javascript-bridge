const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub const ModuleStyle = @import("src/generate_js.zig").ModuleStyle;

pub fn build(b: *std.Build) void {
    /////////////////////////////////////////////////////////////
    // generate js exe
    const generate_js = b.addExecutable(.{
        .name = "generate_js",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generate_js.zig"),
            .target = b.graph.host,
            // Reusing this will occur more often than compiling this, as
            // it usually can be cached.  So faster execution is worth slower
            // initial build.
            .optimize = .debug,
            // .optimize = .ReleaseSafe,
        }),
    });
    b.installArtifact(generate_js);

    /////////////////////////////////////////////////////////////
    // tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generate_js.zig"),
            .target = b.graph.host,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

    /////////////////////////////////////////////////////////////
    // module

    _ = b.addModule("zjb", .{
        .root_source_file = b.path("src/zjb.zig"),
    });
}

pub const BindgenOptions = struct {
    wasm: LazyPath,
    basename: []const u8 = "zjb_bindings.js",
    classname: []const u8 = "Zjb",
    module_style: ModuleStyle = .js,
    minify: bool = false,
};

pub fn bindgen(b: *std.Build, opt: BindgenOptions) LazyPath {
    const dep = b.dependencyFromBuildZig(@This(), .{});
    const generate_js = dep.artifact("generate_js");
    const run = b.addRunArtifact(generate_js);
    const out = run.addPrefixedOutputFileArg("--output=", opt.basename);
    run.addPrefixedFileArg("--wasm=", opt.wasm);
    run.addArg(b.fmt("--class={s}", .{opt.classname}));
    run.addArg(b.fmt("--module-style={s}", .{@tagName(opt.module_style)}));
    run.addArg(b.fmt("--minify={s}", .{if (opt.minify) "true" else "false"}));
    return out;
}
