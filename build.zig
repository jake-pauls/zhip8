const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // EXE
    const exe = b.addExecutable(.{
        .name = "zhip8",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Run
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // SDL
    const zsdl = b.dependency("zsdl", .{});
    exe.root_module.addImport("zsdl2", zsdl.module("zsdl2"));
    @import("zsdl").link_SDL2(exe);

    // SDL Prebuilt-Binaries
    const sdl2_libs_path = b.dependency("sdl2-prebuilt", .{}).path("").getPath(b);
    @import("zsdl").addLibraryPathsTo(sdl2_libs_path, exe);
    @import("zsdl").addRPathsTo(sdl2_libs_path, exe);
    if (@import("zsdl").install_SDL2(b, target.result, sdl2_libs_path, .bin)) |install_sdl2_step| {
        b.getInstallStep().dependOn(install_sdl2_step);
    }
}
