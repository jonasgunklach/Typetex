// tectonic_ffi.h — Public C header for the TectonicFFI static library.
// Generated to match src/lib.rs extern "C" declarations.
// Include this header in bridging headers or Swift Package modulemaps.

#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Result of a LaTeX compilation pass.
/// - On success: pdf_data != NULL, pdf_len > 0, error_message == NULL.
/// - On failure: pdf_data == NULL, pdf_len == 0, error_message != NULL.
/// Must be freed with tectonic_result_free().
typedef struct TectonicResult {
    uint8_t    *pdf_data;       ///< Pointer to PDF bytes (heap-allocated by Rust).
    size_t      pdf_len;        ///< Length of pdf_data in bytes.
    char       *error_message;  ///< UTF-8 error string, or NULL on success.
    char       *log_message;    ///< UTF-8 TeX log string (always present).
} TectonicResult;

/// Compile LaTeX source to PDF using a bundled package ZIP.
///
/// @param tex_source   NUL-terminated UTF-8 LaTeX source.
/// @param bundle_path  NUL-terminated path to the TeX bundle ZIP file.
/// @param extra_files  Reserved, pass NULL.
/// @param extra_count  Reserved, pass 0.
/// @return A TectonicResult — must be freed with tectonic_result_free().
TectonicResult tectonic_compile(
    const char *tex_source,
    const char *bundle_path,
    const char * const *extra_files,
    int extra_count
);

/// Free a TectonicResult returned by tectonic_compile.
/// Must be called exactly once per result.
void tectonic_result_free(TectonicResult *result);

#ifdef __cplusplus
} // extern "C"
#endif
