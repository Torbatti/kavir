const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const zig_version = std.SemanticVersion{
    .major = 0,
    .minor = 13,
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
    const mode = b.standardOptimizeOption(.{});

    // Top-level steps you can invoke on the command line.
    const build_steps = .{
        // .check = b.step("check", "Check if Kavir compiles"),
        .run = b.step("run", "Run Kavir"),
        .fuzz = b.step("fuzz", "Run fuzzers"),
        .@"test" = b.step("test", "Run all tests"),
    };

    // TODO: add options
    // Build options passed with `-D` flags.
    // const build_options = .{};

    const shen_options, const shen_module = build_shen_module(b);

    // build kavir staticly , run kavir
    build_kavir(b, .{
        .run = build_steps.run,
        .install = b.getInstallStep(),
    }, .{
        .shen_module = shen_module,
        .shen_options = shen_options,
        .target = target,
        .mode = mode,
    });
}

fn build_shen_module(
    b: *std.Build,
) struct { *std.Build.Step.Options, *std.Build.Module } {
    // TODO: add options
    const shen_options = b.addOptions();

    const shen_module = b.addModule("shen", .{
        .root_source_file = b.path("src/shen.zig"),
    });

    return .{ shen_options, shen_module };
}

fn build_kavir(
    b: *std.Build,
    steps: struct {
        run: *std.Build.Step,
        install: *std.Build.Step,
    },
    options: struct {
        shen_module: *std.Build.Module,
        shen_options: *std.Build.Step.Options,
        target: std.Build.ResolvedTarget,
        mode: std.builtin.OptimizeMode,
    },
) void {
    const kavir_exe = build_kavir_executable(b, .{
        .shen_module = options.shen_module,
        .shen_options = options.shen_options,
        .target = options.target,
        .mode = options.mode,
    });

    kavir_exe.addCSourceFile(.{
        .file = b.path("include/sqlite3.c"),
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
    kavir_exe.installHeader(b.path("include/sqlite3.h"), "sqlite3.h");

    b.installArtifact(kavir_exe);

    const run_cmd = b.addRunArtifact(kavir_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    steps.run.dependOn(&run_cmd.step);
}

fn build_kavir_executable(b: *std.Build, options: struct {
    shen_module: *std.Build.Module,
    shen_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    mode: std.builtin.OptimizeMode,
}) *std.Build.Step.Compile {
    const kavir = b.addExecutable(.{
        .name = "kavir",
        .root_source_file = b.path("src/kavir/main.zig"),
        .target = options.target,
        .optimize = options.mode,
        .link_libc = true,
    });
    kavir.root_module.addImport("shen", options.shen_module);
    kavir.root_module.addOptions("shen_options", options.shen_options);

    return kavir;
}
