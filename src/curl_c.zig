// This file handles the C imports for curl
// It's compiled as a separate module with proper include paths
pub const c = @cImport({
    @cDefine("CURL_STATICLIB", "1");
    @cInclude("curl/curl.h");
    @cInclude("curl/easy.h");
});
