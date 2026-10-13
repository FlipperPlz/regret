const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const args_dep = b.dependency("args", .{
        .target = target,
        .optimize = optimize,
    });

    const zeit_dep = b.dependency("zeit", .{
        .target = target,
        .optimize = optimize
    });

    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "version", zon.version);

    const strip = b.option(bool, "strip", "Omit debug symbols") orelse false;

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .imports = &.{
            .{ .name = "args", .module = args_dep.module("args") },
            .{ .name = "zeit", .module = zeit_dep.module("zeit") },
        },
    });
    exe_mod.addOptions("build_options", build_opts);

    const exe = b.addExecutable(.{
        .name = "regret",
        .root_module = exe_mod,
    });


// Start first time setup section --------------------------------------------------------------------------------------
    const patch_marker = ".patches_applied";
    const root = b.pathFromRoot(".");

    const needs_setup = blk: {
        b.build_root.handle.access(b.graph.io, patch_marker, .{}) catch {
            break :blk true;
        };
        break :blk false;
    };

    const patch_zeit = b.addSystemCommand(&.{
        "git", "-C", root, "apply",
        "--ignore-whitespace", "--directory=lib/zeit",
        "patches/zeit-fix_timezone_parser.patch",
    });
    patch_zeit.setCwd(.{ .cwd_relative = root });
    patch_zeit.has_side_effects = true;

    const write_marker = b.addUpdateSourceFiles();
    write_marker.addBytesToSource("DO NOT REMOVE UNLESS YOU KNOW WHAT YOUR DOING.\n", patch_marker);
    write_marker.step.dependOn(&patch_zeit.step);

    const say_patching = addPrintStep(b, "Applying zeit timezone patch...");
    patch_zeit.step.dependOn(say_patching);

    const say_done = addPrintStep(b, "Setup complete.");
    say_done.dependOn(&write_marker.step);

    if (needs_setup) exe.step.dependOn(say_done);

// Start clean patches section -----------------------------------------------------------------------------------------
    const reset_submodules = b.addSystemCommand(&.{
        "git", "submodule", "update", "--init", "--recursive", "--force",
    });
    reset_submodules.setCwd(.{ .cwd_relative = root });
    reset_submodules.has_side_effects = true;
    reset_submodules.stdio = .inherit;

    const drop_marker = b.addSystemCommand(&.{ "git", "clean", "-f", "-x", "--", patch_marker });
    drop_marker.setCwd(.{ .cwd_relative = root });
    drop_marker.has_side_effects = true;
    drop_marker.step.dependOn(&reset_submodules.step);

    const clean_patches = b.step("clean_patches", "Reset submodules to pristine state and clear the patch marker");
    clean_patches.dependOn(&drop_marker.step);
// start sync version section ------------------------------------------------------------------------------------------
    const sync = SyncVersion.create(b, "synchronize_version", false, ".version", "build.zig.zon");
    const sync_step = b.step("synchronize_version", "Sync .version in build.zig.zon files from VERSION");
    sync_step.dependOn(&sync.step);
// start clean repo section --------------------------------------------------------------------------------------------
    const rm_outputs = b.addSystemCommand(&.{
        "git", "-C", root, "clean", "-f", "-d", "-x", "--", "zig-out", "zig-pkg", ".zig-cache",
    });
    rm_outputs.setCwd(.{ .cwd_relative = root });
    rm_outputs.has_side_effects = true;
    rm_outputs.stdio = .inherit;
    rm_outputs.step.dependOn(clean_patches);
    rm_outputs.step.dependOn(sync_step);
    const clean_step = b.step("clean", "Remove zig-out, zig-pkg and .zig-cache, and run clean_patches");
    clean_step.dependOn(&rm_outputs.step);

// start remaining steps section ---------------------------------------------------------------------------------------

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

fn addPrintStep(b: *std.Build, comptime msg: []const u8) *std.Build.Step {
    const S = struct {
        fn make(_: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
            std.debug.print(msg ++ "\n", .{});
        }
    };
    const step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = .init(.{
        .id = .custom,
        .name = "print",
        .owner = b,
        .makeFn = S.make,
    });
    return step;
}

const SyncVersion = struct {
    step: std.Build.Step,
    check: bool,
    version_file: []const u8,
    zon_file: []const u8,

    fn create(
        b: *std.Build,
        name: []const u8,
        check: bool,
        version_file: []const u8,
        zon_file: []const u8,
    ) *SyncVersion {
        const self = b.allocator.create(SyncVersion) catch @panic("OOM");
        self.* = .{
            .step = .init(.{
                .id = .custom,
                .name = name,
                .owner = b,
                .makeFn = make,
            }),
            .check = check,
            .version_file = version_file,
            .zon_file = zon_file,
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const self: *SyncVersion = @fieldParentPtr("step", step);
        const b = step.owner;
        const io = b.graph.io;
        const dir = b.build_root.handle;

        const raw = dir.readFileAlloc(io, self.version_file, b.allocator, .limited(1024)) catch |err|
            return step.fail("cannot read {s}: {s}", .{ self.version_file, @errorName(err) });
        const version = std.mem.trim(u8, raw, " \t\r\n");

        var drift = false;
        const src = dir.readFileAlloc(io, self.zon_file, b.allocator, .limited(1 << 20)) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return step.fail("cannot read {s}: {s}", .{ self.zon_file, @errorName(err) }),
        };

        const key = std.mem.indexOf(u8, src, ".version") orelse return;
        const q1 = std.mem.indexOfScalarPos(u8, src, key, '"') orelse return;
        const q2 = std.mem.indexOfScalarPos(u8, src, q1 + 1, '"') orelse return;

        if (std.mem.eql(u8, src[q1 + 1 .. q2], version)) return;

        if (self.check) {
            std.log.err("{s} is out of sync with VERSION ({s})", .{ self.zon_file, version });
            drift = true;
            return;
        }

        const out = try std.mem.concat(b.allocator, u8, &.{ src[0 .. q1 + 1], version, src[q2..] });
        dir.writeFile(io, .{ .sub_path = self.zon_file, .data = out }) catch |err|
            return step.fail("cannot write {s}: {s}", .{ self.zon_file, @errorName(err) });
        std.log.info("{s} -> {s}", .{ self.zon_file, version });

        if (drift) return step.fail("zon versions differ from VERSION; run `zig build synchronize_version`", .{});
    }
};