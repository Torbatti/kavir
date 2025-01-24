const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const zig_version = std.SemanticVersion{
    .major = 0,
    .minor = 14,
    .patch = 0,
};
comptime {
    const zig_version_eq = zig_version.major == builtin.zig_version.major and
        zig_version.minor == builtin.zig_version.minor and
        zig_version.patch == builtin.zig_version.patch;
    if (!zig_version_eq) {
        @compileError(std.fmt.comptimePrint(
            "unsupported zig version: expected {}, found {}",
            .{ zig_version, builtin.zig_version },
        ));
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Top-level steps you can invoke on the command line.
    const build_steps = .{
        // TODO: .check = b.step("check", "Check if Kavir compiles"),
        .run = b.step("run", "Run Kavir"),
        //  TODO: .fuzz = b.step("fuzz", "Run fuzzers"),
        //  TODO: .@"test" = b.step("test", "Run all tests"),
    };

    // Build options passed with `-D` flags.
    const build_options = .{
        .exe_name = b.option(
            []const u8,
            "exe_name",
            "Name of the executable",
        ) orelse "kavir",
        .link_dyn = b.option(
            bool,
            "link_dyn",
            "Link dependencies dynamicly",
        ),
    };

    const lib_options, const lib_module = build_lib_module(
        b,
        .{
            .target = target,
            .mode = optimize,
        },
    );

    // TODO: zig build check

    // zig build, zig build run
    build_kavir_exe(b, .{
        .install = b.getInstallStep(), // zig build
        .run = build_steps.run, // zig build run
    }, .{
        .lib_module = lib_module,
        .lib_options = lib_options,
        .exe_name = build_options.exe_name,
        .link_dyn = build_options.link_dyn,
        .target = target,
        .mode = optimize,
    });
}

fn build_lib_module(
    b: *std.Build,
    options: struct {
        target: std.Build.ResolvedTarget,
        mode: std.builtin.OptimizeMode,
    },
) struct { *std.Build.Step.Options, *std.Build.Module } {

    // TODO: add options
    const lib_options = b.addOptions();

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/kavir.zig"),
        .target = options.target,
        .optimize = options.mode,
    });

    return .{ lib_options, lib_module };
}

fn build_kavir_exe(
    b: *std.Build,
    steps: struct {
        run: *std.Build.Step,
        install: *std.Build.Step,
    },
    options: struct {
        lib_module: *std.Build.Module,
        lib_options: *std.Build.Step.Options,
        exe_name: []const u8,
        link_dyn: ?bool,
        target: std.Build.ResolvedTarget,
        mode: std.builtin.OptimizeMode,
    },
) void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/kavir/main.zig"),
        .target = options.target,
        .optimize = options.mode,
        .link_libc = true,
    });

    const kavir_exe = add_kavir_executable(b, .{
        .lib_module = options.lib_module,
        .lib_options = options.lib_options,
        .exe_name = options.exe_name,
        .exe_module = exe_mod,
        .link_dyn = options.link_dyn,
    });

    b.installArtifact(kavir_exe);

    const run_cmd = b.addRunArtifact(kavir_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    steps.run.dependOn(&run_cmd.step);
}

fn add_kavir_executable(
    b: *std.Build,
    options: struct {
        lib_module: *std.Build.Module,
        lib_options: *std.Build.Step.Options,
        exe_name: []const u8,
        exe_module: *std.Build.Module,
        link_dyn: ?bool,
    },
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = options.exe_name,
        .root_module = options.exe_module,
    });

    // -Dlink_dyn=true
    if (options.link_dyn == true) {
        exe.linkSystemLibrary("sqlite3");
    } else { // will default to staticly linking sqlite
        exe.addCSourceFile(.{
            .file = b.path("lib/sqlite3.c"),
            .flags = &[_][]const u8{
                // default c flags:
                "-Wall",
                "-Wextra",
                "-pedantic",
                "-std=c99",
                // "-std=c2x",

                // Recommended Compile-time Options:
                // https://www.sqlite.org/compile.html
                "-DSQLITE_DQS=0",
                "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
                "-DSQLITE_USE_ALLOCA=1",
                "-DSQLITE_THREADSAFE=1",
                "-DSQLITE_TEMP_STORE=3",
                "-DSQLITE_ENABLE_API_ARMOR=1",
                "-DSQLITE_ENABLE_UNLOCK_NOTIFY",
                "-DSQLITE_ENABLE_UPDATE_DELETE_LIMIT=1",
                "-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600",
                "-DSQLITE_OMIT_DECLTYPE=1",
                "-DSQLITE_OMIT_DEPRECATED=1",
                "-DSQLITE_OMIT_LOAD_EXTENSION=1",
                "-DSQLITE_OMIT_PROGRESS_CALLBACK=1",
                "-DSQLITE_OMIT_SHARED_CACHE",
                "-DSQLITE_OMIT_TRACE=1",
                "-DSQLITE_OMIT_UTF16=1",
                "-DHAVE_USLEEP=0",
            },
        });

        exe.installHeader(b.path("lib/sqlite3.h"), "sqlite3.h");
    }

    exe.root_module.addImport("kavir", options.lib_module);
    exe.root_module.addOptions("kavir_options", options.lib_options);

    return exe;
}
