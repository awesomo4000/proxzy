const std = @import("std");

// This build file provides modules and libraries for static libcurl + mbedTLS
// The main build.zig imports these

pub fn build(b: *std.Build) void {
    // This build file is only used when called directly for testing
    // The main functionality is provided through the exported functions below
    _ = b;
}

pub fn linenoizeModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    // Build the wcwidth dependency first
    const wcwidth = b.addModule("wcwidth", .{
        .root_source_file = b.path("vendor/linenoize/vendor/wcwidth/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the main linenoize module (named "linenoise" to match the library)
    const linenoise = b.addModule("linenoise", .{
        .root_source_file = b.path("vendor/linenoize/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add wcwidth as a dependency to linenoise
    linenoise.addImport("wcwidth", wcwidth);
    
    return linenoise;
}

pub fn buildMbedTLS(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .name = "mbedtls",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = null,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    lib.addIncludePath(b.path("vendor/mbedtls/include"));

    // Core mbedTLS files needed for curl (verified to exist)
    const srcs = [_][]const u8{
        "library/aes.c",
        "library/aesce.c",
        "library/aesni.c",
        "library/aria.c",
        "library/asn1parse.c",
        "library/asn1write.c",
        "library/base64.c",
        "library/bignum.c",
        "library/bignum_core.c",
        "library/bignum_mod.c",
        "library/bignum_mod_raw.c",
        "library/camellia.c",
        "library/ccm.c",
        "library/chacha20.c",
        "library/chachapoly.c",
        "library/cipher.c",
        "library/cipher_wrap.c",
        "library/constant_time.c",
        "library/cmac.c",
        "library/ctr_drbg.c",
        "library/debug.c",
        "library/des.c",
        "library/dhm.c",
        "library/ecdh.c",
        "library/ecdsa.c",
        "library/ecjpake.c",
        "library/ecp.c",
        "library/ecp_curves.c",
        "library/ecp_curves_new.c",
        "library/entropy.c",
        "library/entropy_poll.c",
        "library/error.c",
        "library/gcm.c",
        "library/hkdf.c",
        "library/hmac_drbg.c",
        "library/nist_kw.c",
        "library/md.c",
        "library/md5.c",
        "library/net_sockets.c",
        "library/oid.c",
        "library/pem.c",
        "library/pk.c",
        "library/pk_ecc.c",
        "library/pk_wrap.c",
        "library/pkcs12.c",
        "library/pkcs5.c",
        "library/pkparse.c",
        "library/pkwrite.c",
        "library/platform.c",
        "library/platform_util.c",
        "library/poly1305.c",
        "library/psa_crypto.c",
        "library/psa_crypto_aead.c",
        "library/psa_crypto_cipher.c",
        "library/psa_crypto_client.c",
        "library/psa_crypto_driver_wrappers_no_static.c",
        "library/psa_crypto_ecp.c",
        "library/psa_crypto_ffdh.c",
        "library/psa_crypto_hash.c",
        "library/psa_crypto_mac.c",
        "library/psa_crypto_pake.c",
        "library/psa_crypto_rsa.c",
        "library/psa_crypto_se.c",
        "library/psa_crypto_slot_management.c",
        "library/psa_crypto_storage.c",
        "library/psa_its_file.c",
        "library/psa_util.c",
        "library/ripemd160.c",
        "library/rsa.c",
        "library/rsa_alt_helpers.c",
        "library/sha1.c",
        "library/sha256.c",
        "library/sha512.c",
        "library/sha3.c",
        "library/ssl_cache.c",
        "library/ssl_ciphersuites.c",
        "library/ssl_client.c",
        "library/ssl_cookie.c",
        "library/ssl_debug_helpers_generated.c",
        "library/ssl_msg.c",
        "library/ssl_ticket.c",
        "library/ssl_tls.c",
        "library/ssl_tls12_client.c",
        "library/ssl_tls12_server.c",
        "library/ssl_tls13_client.c",
        "library/ssl_tls13_generic.c",
        "library/ssl_tls13_keys.c",
        "library/ssl_tls13_server.c",
        "library/threading.c",
        "library/timing.c",
        "library/version.c",
        "library/version_features.c",
        "library/x509.c",
        "library/x509_create.c",
        "library/x509_crl.c",
        "library/x509_crt.c",
        "library/x509_csr.c",
        "library/x509write.c",
        "library/x509write_crt.c",
        "library/x509write_csr.c",
    };

    // Determine compile flags based on target OS
    const cflags = switch (target.result.os.tag) {
        .freebsd => &[_][]const u8{
            "-std=c99",
            "-D__BSD_VISIBLE",
            "-fno-sanitize=alignment",
        },
        .openbsd, .netbsd, .dragonfly => &[_][]const u8{
            "-std=c99",
            "-D_BSD_SOURCE",
            "-D_DEFAULT_SOURCE",
            "-fno-sanitize=alignment",
        },
        else => &[_][]const u8{
            "-std=c99",
            "-D_POSIX_C_SOURCE=200112L",
            "-fno-sanitize=alignment",
        },
    };

    for (srcs) |src| {
        lib.addCSourceFile(.{
            .file = b.path(b.fmt("vendor/mbedtls/{s}", .{src})),
            .flags = cflags,
        });
    }

    return lib;
}

pub fn buildCurl(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .name = "curl",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = null,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    lib.addIncludePath(b.path("vendor/libcurl/include"));
    lib.addIncludePath(b.path("vendor/libcurl/src"));
    lib.addIncludePath(b.path("vendor/mbedtls/include"));

    // Define all necessary macros (based on jiacai2050/zig-curl approach)
    lib.root_module.addCMacro("BUILDING_LIBCURL", "1");
    lib.root_module.addCMacro("CURL_STATICLIB", "1");
    lib.root_module.addCMacro("USE_MBEDTLS", "1");
    lib.root_module.addCMacro("CURL_DISABLE_LDAP", "1");
    lib.root_module.addCMacro("CURL_DISABLE_LDAPS", "1");
    lib.root_module.addCMacro("CURL_DISABLE_DICT", "1");
    lib.root_module.addCMacro("CURL_DISABLE_FILE", "1");
    lib.root_module.addCMacro("CURL_DISABLE_FTP", "1");
    lib.root_module.addCMacro("CURL_DISABLE_GOPHER", "1");
    lib.root_module.addCMacro("CURL_DISABLE_IMAP", "1");
    lib.root_module.addCMacro("CURL_DISABLE_MQTT", "1");
    lib.root_module.addCMacro("CURL_DISABLE_POP3", "1");
    lib.root_module.addCMacro("CURL_DISABLE_RTSP", "1");
    lib.root_module.addCMacro("CURL_DISABLE_SMB", "1");
    lib.root_module.addCMacro("CURL_DISABLE_SMTP", "1");
    lib.root_module.addCMacro("CURL_DISABLE_TELNET", "1");
    lib.root_module.addCMacro("CURL_DISABLE_TFTP", "1");
    lib.root_module.addCMacro("ENABLE_QUIC", "0");

    // Platform-specific macros
    const isDarwin = target.result.os.tag.isDarwin();
    const isWindows = target.result.os.tag == .windows;

    if (!isWindows) {
        lib.root_module.addCMacro("HAVE_ARPA_INET_H", "1");
        lib.root_module.addCMacro("HAVE_FCNTL_H", "1");
        lib.root_module.addCMacro("HAVE_NETDB_H", "1");
        lib.root_module.addCMacro("HAVE_NETINET_IN_H", "1");
        lib.root_module.addCMacro("HAVE_NETINET_TCP_H", "1");
        lib.root_module.addCMacro("HAVE_POLL_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_IOCTL_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_SELECT_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_SOCKET_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_TIME_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_TYPES_H", "1");
        lib.root_module.addCMacro("HAVE_UNISTD_H", "1");
        lib.root_module.addCMacro("HAVE_ALARM", "1");
        lib.root_module.addCMacro("HAVE_FCNTL", "1");
        lib.root_module.addCMacro("HAVE_FCNTL_O_NONBLOCK", "1");
        lib.root_module.addCMacro("HAVE_GETHOSTBYNAME", "1");
        lib.root_module.addCMacro("HAVE_GETPPID", "1");
        lib.root_module.addCMacro("HAVE_GETTIMEOFDAY", "1");
        lib.root_module.addCMacro("HAVE_PIPE", "1");
        lib.root_module.addCMacro("HAVE_SELECT", "1");
        lib.root_module.addCMacro("HAVE_SOCKET", "1");
        lib.root_module.addCMacro("HAVE_SOCKETPAIR", "1");
        lib.root_module.addCMacro("HAVE_UNAME", "1");

        if (!isDarwin) {
            lib.root_module.addCMacro("HAVE_POLL", "1");
            lib.root_module.addCMacro("HAVE_MSG_NOSIGNAL", "1");
        }
    }

    // Common macros for all platforms
    lib.root_module.addCMacro("HAVE_ASSERT_H", "1");
    lib.root_module.addCMacro("HAVE_BOOL_T", "1");
    lib.root_module.addCMacro("HAVE_SYS_STAT_H", "1");
    lib.root_module.addCMacro("CURL_OS", "\"Unix\"");
    lib.root_module.addCMacro("HAVE_ERRNO_H", "1");
    lib.root_module.addCMacro("HAVE_INTTYPES_H", "1");
    lib.root_module.addCMacro("HAVE_LIMITS_H", "1");
    lib.root_module.addCMacro("HAVE_LONGLONG", "1");
    lib.root_module.addCMacro("HAVE_MEMORY_H", "1");
    lib.root_module.addCMacro("HAVE_RECV", "1");
    lib.root_module.addCMacro("HAVE_SEND", "1");
    lib.root_module.addCMacro("HAVE_SIGNAL", "1");
    lib.root_module.addCMacro("HAVE_SIGNAL_H", "1");
    lib.root_module.addCMacro("HAVE_STDATOMIC_H", "1");
    lib.root_module.addCMacro("HAVE_STDBOOL_H", "1");
    lib.root_module.addCMacro("HAVE_STDINT_H", "1");
    lib.root_module.addCMacro("HAVE_STDIO_H", "1");
    lib.root_module.addCMacro("HAVE_STDLIB_H", "1");
    lib.root_module.addCMacro("HAVE_STRING_H", "1");
    lib.root_module.addCMacro("HAVE_STRINGS_H", "1");
    lib.root_module.addCMacro("HAVE_STRUCT_TIMEVAL", "1");
    lib.root_module.addCMacro("HAVE_TIME_H", "1");
    lib.root_module.addCMacro("HAVE_VARIADIC_MACROS_C99", "1");
    lib.root_module.addCMacro("HAVE_VARIADIC_MACROS_GCC", "1");

    // Type definitions
    lib.root_module.addCMacro("RECV_TYPE_ARG1", "int");
    lib.root_module.addCMacro("RECV_TYPE_ARG2", "void *");
    lib.root_module.addCMacro("RECV_TYPE_ARG3", "size_t");
    lib.root_module.addCMacro("RECV_TYPE_ARG4", "int");
    lib.root_module.addCMacro("RECV_TYPE_RETV", "ssize_t");
    lib.root_module.addCMacro("SEND_QUAL_ARG2", "const");
    lib.root_module.addCMacro("SEND_TYPE_ARG1", "int");
    lib.root_module.addCMacro("SEND_TYPE_ARG2", "void *");
    lib.root_module.addCMacro("SEND_TYPE_ARG3", "size_t");
    lib.root_module.addCMacro("SEND_TYPE_ARG4", "int");
    lib.root_module.addCMacro("SEND_TYPE_RETV", "ssize_t");

    lib.root_module.addCMacro("SIZEOF_INT", "4");
    lib.root_module.addCMacro("SIZEOF_SHORT", "2");
    lib.root_module.addCMacro("SIZEOF_LONG", "8");
    lib.root_module.addCMacro("SIZEOF_OFF_T", "8");
    lib.root_module.addCMacro("SIZEOF_CURL_OFF_T", "8");
    lib.root_module.addCMacro("SIZEOF_SIZE_T", "8");
    lib.root_module.addCMacro("SIZEOF_TIME_T", "8");

    lib.root_module.addCMacro("STDC_HEADERS", "1");

    // Essential curl source files for HTTP/HTTPS
    const srcs = [_][]const u8{
        // Core
        "altsvc.c",
        "asyn-base.c",
        "asyn-thrdd.c",
        "bufq.c",
        "bufref.c",
        "cf-h1-proxy.c",
        "cf-h2-proxy.c",
        "cf-haproxy.c",
        "cf-https-connect.c",
        "cf-ip-happy.c",
        "cf-socket.c",
        "cfilters.c",
        "conncache.c",
        "connect.c",
        "content_encoding.c",
        "cookie.c",
        "cshutdn.c",
        "curl_addrinfo.c",
        "curl_des.c",
        "curl_endian.c",
        "curl_fnmatch.c",
        "curl_get_line.c",
        "curl_gethostname.c",
        "curl_gssapi.c",
        "curl_memrchr.c",
        "curl_ntlm_core.c",
        "curl_range.c",
        "curl_rtmp.c",
        "curl_sasl.c",
        "curl_sha512_256.c",
        "curl_sspi.c",
        "curl_threads.c",
        "curl_trc.c",
        "cw-out.c",
        "cw-pause.c",
        "dict.c",
        "dllmain.c",
        "doh.c",
        "dynhds.c",
        "easy.c",
        "escape.c",
        "fake_addrinfo.c",
        "file.c",
        "fileinfo.c",
        "fopen.c",
        "formdata.c",
        "ftp.c",
        "ftplistparser.c",
        "getenv.c",
        "getinfo.c",
        "gopher.c",
        "hash.c",
        "headers.c",
        "hmac.c",
        "hostip.c",
        "hostip4.c",
        "hostip6.c",
        "hsts.c",
        "http.c",
        "http1.c",
        "http2.c",
        "http_aws_sigv4.c",
        "http_chunks.c",
        "http_digest.c",
        "http_negotiate.c",
        "http_ntlm.c",
        "http_proxy.c",
        "httpsrr.c",
        "idn.c",
        "if2ip.c",
        "imap.c",
        "krb5.c",
        "ldap.c",
        "llist.c",
        "macos.c",
        "md4.c",
        "md5.c",
        "memdebug.c",
        "mime.c",
        "mprintf.c",
        "mqtt.c",
        "multi.c",
        "multi_ev.c",
        "netrc.c",
        "noproxy.c",
        "openldap.c",
        "parsedate.c",
        "pingpong.c",
        "pop3.c",
        "progress.c",
        "psl.c",
        "rand.c",
        "rename.c",
        "request.c",
        "rtsp.c",
        "select.c",
        "sendf.c",
        "setopt.c",
        "sha256.c",
        "share.c",
        "slist.c",
        "smb.c",
        "smtp.c",
        "socketpair.c",
        "socks.c",
        "socks_gssapi.c",
        "socks_sspi.c",
        "speedcheck.c",
        "splay.c",
        "strcase.c",
        "strdup.c",
        "strequal.c",
        "strerror.c",
        "telnet.c",
        "tftp.c",
        "transfer.c",
        "uint-bset.c",
        "uint-hash.c",
        "uint-spbset.c",
        "uint-table.c",
        "url.c",
        "urlapi.c",
        "version.c",
        "ws.c",

        // curlx - utility functions (new in 8.16.0)
        "curlx/base64.c",
        "curlx/dynbuf.c",
        "curlx/inet_ntop.c",
        "curlx/inet_pton.c",
        "curlx/multibyte.c",
        "curlx/nonblock.c",
        "curlx/strparse.c",
        "curlx/timediff.c",
        "curlx/timeval.c",
        "curlx/wait.c",
        "curlx/warnless.c",
        "curlx/winapi.c",

        // VTLS
        "vtls/cipher_suite.c",
        "vtls/gtls.c",
        "vtls/hostcheck.c",
        "vtls/keylog.c",
        "vtls/mbedtls.c",
        "vtls/mbedtls_threadlock.c",
        "vtls/openssl.c",
        "vtls/rustls.c",
        "vtls/schannel.c",
        "vtls/schannel_verify.c",
        "vtls/vtls.c",
        "vtls/vtls_scache.c",
        "vtls/vtls_spack.c",
        "vtls/wolfssl.c",
        "vtls/x509asn1.c",

        // vauth
        "vauth/cleartext.c",
        "vauth/cram.c",
        "vauth/digest.c",
        "vauth/digest_sspi.c",
        "vauth/gsasl.c",
        "vauth/krb5_gssapi.c",
        "vauth/krb5_sspi.c",
        "vauth/ntlm.c",
        "vauth/ntlm_sspi.c",
        "vauth/oauth2.c",
        "vauth/spnego_gssapi.c",
        "vauth/spnego_sspi.c",
        "vauth/vauth.c",

        // vquic
        "vquic/vquic.c",

        // vssh
        "vssh/libssh.c",
        "vssh/libssh2.c",
        "vssh/wolfssh.c",
    };

    // Determine compile flags based on target
    const cflags = switch (target.result.os.tag) {
        .linux => &[_][]const u8{ "-std=c99", "-w", "-fno-sanitize=alignment", "-D_GNU_SOURCE" },
        .freebsd => &[_][]const u8{
            "-std=c99",
            "-w",
            "-fno-sanitize=alignment",
            "-D__BSD_VISIBLE"
        },
        .openbsd, .netbsd, .dragonfly => &[_][]const u8{
            "-std=c99",
            "-w",
            "-fno-sanitize=alignment",
            "-D_BSD_SOURCE",
            "-D_DEFAULT_SOURCE"
        },
        else => &[_][]const u8{ "-std=c99", "-w", "-fno-sanitize=alignment" },
    };

    for (srcs) |src| {
        lib.addCSourceFile(.{
            .file = b.path(b.fmt("vendor/libcurl/src/{s}", .{src})),
            .flags = cflags,
        });
    }

    // Add Windows-specific files
    if (isWindows) {
        lib.addCSourceFile(.{
            .file = b.path("vendor/libcurl/src/system_win32.c"),
            .flags = &.{ "-std=c99", "-w" },
        });
        lib.addCSourceFile(.{
            .file = b.path("vendor/libcurl/src/curlx/version_win32.c"),
            .flags = &.{ "-std=c99", "-w" },
        });
        lib.root_module.addCMacro("WIN32", "1");
        lib.root_module.addCMacro("_WIN32", "1");
        lib.root_module.addCMacro("HAVE_WINDOWS_H", "1");
        lib.root_module.addCMacro("HAVE_WINSOCK2_H", "1");
        lib.root_module.addCMacro("HAVE_WS2TCPIP_H", "1");
    }

    return lib;
}

pub fn createCurlClientStreamingModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("convo/curl_client_streaming.zig"),
        .target = target,
        .optimize = optimize,
    });
}

pub fn microwaveModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("vendor/microwave/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
}

pub fn clipboardModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Module {
    // Return null if clipboard should not be included
    // The caller should check if clipboard is enabled
    return b.createModule(.{
        .root_source_file = b.path("vendor/nclip2-lib/src/clipboard.zig"),
        .target = target,
        .optimize = optimize,
    });
}
