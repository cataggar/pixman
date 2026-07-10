const std = @import("std");

// Portable (non-SIMD) pixman sources: the reference C implementation used by
// pixman-general.c / pixman-fast-path.c / pixman-noop.c is correct on every
// target on its own; the various *-mmx/-sse2/-ssse3/-vmx/-neon/-rvv files are
// optional performance fast paths that pixman's meson.build only enables
// after probing the compiler for arch-specific intrinsic/inline-asm support.
// This build.zig skips that probing (and those optional backends) to keep
// things simple: it builds only the portable sources meson always builds.
const pixman_sources = [_][]const u8{
    "pixman.c",
    "pixman-access.c",
    "pixman-access-accessors.c",
    "pixman-arm.c",
    "pixman-bits-image.c",
    "pixman-combine32.c",
    "pixman-combine-float.c",
    "pixman-conical-gradient.c",
    "pixman-edge.c",
    "pixman-edge-accessors.c",
    "pixman-fast-path.c",
    "pixman-filter.c",
    "pixman-glyph.c",
    "pixman-general.c",
    "pixman-gradient-walker.c",
    "pixman-image.c",
    "pixman-implementation.c",
    "pixman-linear-gradient.c",
    "pixman-matrix.c",
    "pixman-mips.c",
    "pixman-noop.c",
    "pixman-ppc.c",
    "pixman-radial-gradient.c",
    "pixman-region16.c",
    "pixman-region32.c",
    "pixman-region64f.c",
    "pixman-riscv.c",
    "pixman-solid-fill.c",
    "pixman-timer.c",
    "pixman-trap.c",
    "pixman-utils.c",
    "pixman-x86.c",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // `long` is 4 bytes on Windows (LLP64) but 8 bytes on Linux/macOS
    // (LP64); pixman-fast-path.c branches on this via `#if SIZEOF_LONG`,
    // so it must match the target, not just the host.
    const sizeof_long = target.result.cTypeByteSize(.long);

    // meson normally generates pixman-config.h itself from a bunch of
    // compiler probes (see meson.build/meson.options upstream); this is a
    // hand-written stand-in with just the defines pixman's portable
    // sources actually need. Notably TLS is set to `__thread` (supported
    // by zig cc/clang on every target) instead of probing for MSVC
    // `__declspec(thread)` or pthreads, so no pthread dependency is needed.
    const write_files = b.addWriteFiles();
    _ = write_files.add("pixman-config.h", b.fmt(
        \\#ifndef PIXMAN_CONFIG_H
        \\#define PIXMAN_CONFIG_H
        \\
        \\#define PACKAGE "pixman"
        \\#define SIZEOF_LONG {d}
        \\#define TLS __thread
        \\#define TOOLCHAIN_SUPPORTS_ATTRIBUTE_CONSTRUCTOR 1
        \\#define TOOLCHAIN_SUPPORTS_ATTRIBUTE_DESTRUCTOR 1
        \\#define HAVE_BUILTIN_CLZ 1
        \\
        \\#endif
        \\
    , .{sizeof_long}));

    // Stand-in for the pixman-version.h meson generates from
    // pixman/pixman-version.h.in (@PIXMAN_VERSION_*@ substitution), with
    // the version numbers from this build.zig.zon baked in directly.
    const version_h = write_files.add("pixman-version.h",
        \\#ifndef PIXMAN_VERSION_H__
        \\#define PIXMAN_VERSION_H__
        \\
        \\#ifndef PIXMAN_H__
        \\#  error pixman-version.h should only be included by pixman.h
        \\#endif
        \\
        \\#define PIXMAN_VERSION_MAJOR 0
        \\#define PIXMAN_VERSION_MINOR 46
        \\#define PIXMAN_VERSION_MICRO 5
        \\
        \\#define PIXMAN_VERSION_STRING "0.46.5"
        \\
        \\#define PIXMAN_VERSION_ENCODE(major, minor, micro) ( \
        \\      ((major) * 10000)                \
        \\    + ((minor) *   100)                \
        \\    + ((micro) *     1))
        \\
        \\#define PIXMAN_VERSION PIXMAN_VERSION_ENCODE(    \
        \\    PIXMAN_VERSION_MAJOR,            \
        \\    PIXMAN_VERSION_MINOR,            \
        \\    PIXMAN_VERSION_MICRO)

        \\
        \\#ifndef PIXMAN_API
        \\# define PIXMAN_API
        \\#endif
        \\
        \\#endif /* PIXMAN_VERSION_H__ */
        \\
    );
    const generated_headers = write_files.getDirectory();

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(generated_headers);
    mod.addIncludePath(b.path("pixman"));
    mod.addCMacro("HAVE_CONFIG_H", "1");
    mod.addCSourceFiles(.{
        .root = b.path("pixman"),
        .files = &pixman_sources,
        .flags = &.{
            "-std=gnu99",
            "-fno-strict-aliasing",
        },
    });

    const lib = b.addLibrary(.{
        .name = "pixman-1",
        .linkage = .static,
        .root_module = mod,
    });
    lib.installHeader(b.path("pixman/pixman.h"), "pixman-1/pixman.h");
    lib.installHeader(version_h, "pixman-1/pixman-version.h");
    b.installArtifact(lib);
}
