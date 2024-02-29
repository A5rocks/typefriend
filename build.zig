const std = @import("std");
const relative_path = std.Build.LazyPath.relative;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ziglyph = b.dependency("ziglyph", .{ .optimize = optimize, .target = target });

    if (b.option([]const u8, "python-exe", "Python executable to build for")) |python| {
        const libtypefriend = b.addSharedLibrary(.{
            .name = "typefriend",
            .root_source_file = relative_path("src/py_interface.zig"),
            .target = target,
            .optimize = optimize,
        });

        var res = try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{ python, "-c", "import sysconfig; print(sysconfig.get_path('include'), end='')"}
        });

        libtypefriend.root_module.addImport("ziglyph", ziglyph.module("ziglyph"));
        libtypefriend.root_module.addIncludePath(.{.cwd_relative = res.stdout});
        libtypefriend.linkLibC();
        b.allocator.free(res.stdout);
        b.allocator.free(res.stderr);

        res = try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{ python, "-c", "import sys; print(sys.base_prefix, end='')"}
        });

        // possibly windows-only
        libtypefriend.root_module.addObjectFile(.{.cwd_relative = b.pathJoin(&.{res.stdout, "libs", "python3.lib"})});
        b.installArtifact(libtypefriend);
        b.allocator.free(res.stdout);
        b.allocator.free(res.stderr);
    } else {
        const exe = b.addExecutable(.{
            .name = "typefriend",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("ziglyph", ziglyph.module("ziglyph"));
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        // tests (TODO: add -Dsnapshot=true / false)
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        unit_tests.root_module.addImport("ziglyph", ziglyph.module("ziglyph"));
        const run_unit_tests = b.addRunArtifact(unit_tests);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    }
}
