const std = @import("std");
const zon = @import("build.zig.zon");

const Step = std.Build.Step;

const version_file = ".version";
const zon_file = "build.zig.zon";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Omit debug symbols") orelse false;

    const exe = addExe(b, target, optimize, strip);
    b.installArtifact(exe);

    if (Patches.needsSetup(b)) exe.step.dependOn(try Patches.addSetup(b));

    const warn_build = try SyncVersion.create(b, "warn_version_build", .warn);
    exe.step.dependOn(&warn_build.step);

    const clean_patches = Patches.addCleanStep(b);
    const sync_version = try addVersionSteps(b);
    addCleanStep(b, &.{ clean_patches, sync_version });

    try addRunStep(b, exe);
    addTestStep(b, exe);
}

fn addExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
) *Step.Compile {
    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "version", zon.version);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .imports = &.{
            .{ .name = "args", .module = depModule(b, "args", target, optimize) },
            .{ .name = "zeit", .module = depModule(b, "zeit", target, optimize) },
        },
    });
    exe_mod.addOptions("build_options", build_opts);

    return b.addExecutable(.{
        .name = "regret",
        .root_module = exe_mod,
    });
}

fn depModule(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const dep = b.dependency(name, .{ .target = target, .optimize = optimize });
    return dep.module(name);
}

fn addVersionSteps(b: *std.Build) !*Step {
    const sync = try SyncVersion.create(b, "sync_version", .sync);
    const sync_step = b.step("sync_version", "Sync version in " ++ zon_file ++ " from " ++ version_file);
    sync_step.dependOn(&sync.step);

    const desync = try DesyncVersion.create(b, "desync_version", zon.version);
    const desync_step = b.step("desync_version", "Reset " ++ version_file ++ " to the version in " ++ zon_file);
    desync_step.dependOn(&desync.step);

    return sync_step;
}

fn addCleanStep(b: *std.Build, deps: []const *Step) void {
    const rm_outputs = addGit(
        b,
        &.{ "clean", "-f", "-d", "-x", "--", "zig-out", "zig-pkg", ".zig-cache" },
        .{ .inherit_stdio = true },
    );
    for (deps) |dep| rm_outputs.step.dependOn(dep);

    const clean = b.step("clean", "Reset submodules to pristine state, clear the patch marker, remove zig temp dirs");
    clean.dependOn(&rm_outputs.step);
}

fn addRunStep(b: *std.Build, exe: *Step.Compile) !void {
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const warn = try SyncVersion.create(b, "warn_version_run", .warn);
    warn.step.dependOn(&run_cmd.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    run_step.dependOn(&warn.step);
}

fn addTestStep(b: *std.Build, exe: *Step.Compile) void {
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}

const GitOptions = struct {
    inherit_stdio: bool = false,
};

fn addGit(b: *std.Build, args: []const []const u8, opts: GitOptions) *Step.Run {
    const run = b.addSystemCommand(&.{"git"});
    run.addArgs(args);
    run.setCwd(.{ .cwd_relative = b.pathFromRoot(".") });
    run.has_side_effects = true;
    if (opts.inherit_stdio) run.stdio = .inherit;
    return run;
}

fn customStep(b: *std.Build, name: []const u8, make: Step.MakeFn) Step {
    return .init(.{
        .id = .custom,
        .name = name,
        .owner = b,
        .makeFn = make,
    });
}

fn readVersionFile(b: *std.Build) ![]const u8 {
    const raw = try b.build_root.handle.readFileAlloc(b.graph.io, version_file, b.allocator, .limited(1024));
    return std.mem.trim(u8, raw, " \t\r\n");
}

const Patches = struct {
    const marker = ".patches_applied";
    const zeit_patch = "patches/zeit-fix_timezone_parser.patch";

    fn needsSetup(b: *std.Build) bool {
        b.build_root.handle.access(b.graph.io, marker, .{}) catch return true;
        return false;
    }

    fn addSetup(b: *std.Build) !*Step {
        const say_patching = try PrintStep.create(b, "Applying zeit timezone patch...");

        const apply = addGit(b, &.{
            "apply",
            "--ignore-whitespace",
            "--directory=lib/zeit",
            zeit_patch,
        }, .{});
        apply.step.dependOn(&say_patching.step);

        const write_marker = b.addUpdateSourceFiles();
        write_marker.addBytesToSource("DO NOT REMOVE UNLESS YOU KNOW WHAT YOU'RE DOING.\n", marker);
        write_marker.step.dependOn(&apply.step);

        const say_done = try PrintStep.create(b, "Setup complete.");
        say_done.step.dependOn(&write_marker.step);

        return &say_done.step;
    }

    fn addCleanStep(b: *std.Build) *Step {
        const reset_submodules = addGit(
            b,
            &.{ "submodule", "update", "--init", "--recursive", "--force" },
            .{ .inherit_stdio = true },
        );

        const drop_marker = addGit(b, &.{ "clean", "-f", "-X", "--", marker }, .{});
        drop_marker.step.dependOn(&reset_submodules.step);

        const step = b.step("clean_patches", "Reset submodules to pristine state and clear the patch marker");
        step.dependOn(&drop_marker.step);
        return step;
    }
};

const PrintStep = struct {
    step: Step,
    msg: []const u8,

    fn create(b: *std.Build, msg: []const u8) !*PrintStep {
        const self = try b.allocator.create(PrintStep);
        self.* = .{
            .step = customStep(b, "print", make),
            .msg = b.dupe(msg),
        };
        return self;
    }

    fn make(step: *Step, _: Step.MakeOptions) !void {
        const self: *PrintStep = @fieldParentPtr("step", step);
        std.debug.print("{s}\n", .{self.msg});
    }
};

const SyncVersion = struct {
    pub const Mode = enum { sync, check, warn };

    step: Step,
    mode: Mode,

    fn create(b: *std.Build, name: []const u8, mode: Mode) !*SyncVersion {
        const self = try b.allocator.create(SyncVersion);
        self.* = .{
            .step = customStep(b, name, make),
            .mode = mode,
        };
        return self;
    }

    fn make(step: *Step, _: Step.MakeOptions) !void {
        const self: *SyncVersion = @fieldParentPtr("step", step);
        const b = step.owner;
        const io = b.graph.io;
        const dir = b.build_root.handle;

        const version = readVersionFile(b) catch |err| return self.cannotRead(version_file, err);

        const src = dir.readFileAlloc(io, zon_file, b.allocator, .limited(1 << 20)) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return self.cannotRead(zon_file, err),
        };

        const loc = ZonVersion.find(src) orelse return;
        const zon_version = src[loc.start..loc.end];
        if (std.mem.eql(u8, zon_version, version)) return;

        switch (self.mode) {
            .warn => {
                std.debug.print(
                    "warning: {s} has version {s} but {s} has {s}. Run `zig build sync_version`.\n",
                    .{ zon_file, zon_version, version_file, version },
                );
                return;
            },
            .check => return step.fail(
                "{s} has version {s} but {s} has {s}; run zig build sync_version",
                .{ zon_file, zon_version, version_file, version },
            ),
            .sync => {},
        }
        const out = std.mem.concat(b.allocator, u8, &.{ src[0..loc.start], version, src[loc.end..] }) catch |err|
            return step.fail("OOM while synchronizing versions: {s}", .{@errorName(err)});

        dir.writeFile(io, .{ .sub_path = zon_file, .data = out }) catch |err|
            return step.fail("cannot write {s}: {s}", .{ zon_file, @errorName(err) });

        std.log.info("{s} -> {s}", .{ zon_file, version });
    }

    fn cannotRead(self: *SyncVersion, path: []const u8, err: anyerror) !void {
        if (self.mode == .warn) return;
        return self.step.fail("cannot read {s}: {s}", .{ path, @errorName(err) });
    }
};

const ZonVersion = struct {
    start: usize,
    end: usize,

    fn find(src: []const u8) ?ZonVersion {
        const key = std.mem.indexOf(u8, src, ".version") orelse return null;
        const open = std.mem.indexOfScalarPos(u8, src, key, '"') orelse return null;
        const close = std.mem.indexOfScalarPos(u8, src, open + 1, '"') orelse return null;
        return .{ .start = open + 1, .end = close };
    }
};

const DesyncVersion = struct {
    step: Step,
    zon_version: []const u8,

    fn create(b: *std.Build, name: []const u8, zon_version: []const u8) !*DesyncVersion {
        const self = try b.allocator.create(DesyncVersion);
        self.* = .{
            .step = customStep(b, name, make),
            .zon_version = zon_version,
        };
        return self;
    }

    fn make(step: *Step, _: Step.MakeOptions) !void {
        const self: *DesyncVersion = @fieldParentPtr("step", step);
        const b = step.owner;
        if (readVersionFile(b)) |current| {
            if (std.mem.eql(u8, current, self.zon_version)) return;
        } else |_| {}
        const out = std.fmt.allocPrint(b.allocator, "{s}\n", .{self.zon_version}) catch |err|
            return step.fail("OOM writing version file: {s}", .{@errorName(err)});
        b.build_root.handle.writeFile(b.graph.io, .{ .sub_path = version_file, .data = out }) catch |err|
            return step.fail("cannot write {s}: {s}", .{ version_file, @errorName(err) });
        std.log.info("{s} -> {s} (from {s})", .{ version_file, self.zon_version, zon_file });
    }
};