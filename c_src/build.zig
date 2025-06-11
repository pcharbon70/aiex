const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    // Create the shared library for the NIF
    const lib = b.addSharedLibrary(.{
        .name = "libvaxis_nif",
        .root_source_file = b.path("libvaxis_nif.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add Zigler beam module
    lib.addModule("beam", b.dependency("beam", .{}).module("beam"));
    
    // Add Libvaxis dependency
    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    lib.addModule("vaxis", vaxis.module("vaxis"));
    
    // Link with necessary libraries
    lib.linkLibC();
    
    // Install the library
    b.installArtifact(lib);
}