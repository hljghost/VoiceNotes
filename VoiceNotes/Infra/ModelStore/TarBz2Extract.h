#ifndef VoiceNotes_TarBz2Extract_h
#define VoiceNotes_TarBz2Extract_h

#ifdef __cplusplus
extern "C" {
#endif

/// Extract selected regular files from a `.tar.bz2` archive into `dest_dir`.
/// Matching is by exact archive path or basename.
/// Returns 0 on success (all wanted files extracted).
int voicenotes_extract_tar_bz2(
    const char *archive_path,
    const char *dest_dir,
    const char **wanted_names,
    int wanted_count
);

#ifdef __cplusplus
}
#endif

#endif /* VoiceNotes_TarBz2Extract_h */
