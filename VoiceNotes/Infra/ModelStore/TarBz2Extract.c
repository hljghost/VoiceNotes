#include "TarBz2Extract.h"

#include <bzlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

enum {
    kTarBlock = 512,
    kReadChunk = 64 * 1024
};

static int ensure_dir(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode) ? 0 : -1;
    }
    return mkdir(path, 0755);
}

static int name_wanted(const char *name, const char **wanted, int wanted_count) {
    for (int i = 0; i < wanted_count; i++) {
        if (strcmp(name, wanted[i]) == 0) {
            return 1;
        }
        /* Also match basename when archive uses folder/prefix. */
        const char *slash = strrchr(name, '/');
        if (slash && strcmp(slash + 1, wanted[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

static unsigned long long parse_octal(const char *buf, size_t len) {
    unsigned long long value = 0;
    for (size_t i = 0; i < len; i++) {
        char c = buf[i];
        if (c == '\0' || c == ' ') {
            break;
        }
        if (c < '0' || c > '7') {
            break;
        }
        value = (value << 3) + (unsigned long long)(c - '0');
    }
    return value;
}

static int read_decompressed(
    BZFILE *bz,
    char *out,
    int need,
    int *bzerror
) {
    int got = 0;
    while (got < need) {
        int n = BZ2_bzRead(bzerror, bz, out + got, need - got);
        if (*bzerror == BZ_STREAM_END) {
            got += n;
            break;
        }
        if (*bzerror != BZ_OK) {
            return -1;
        }
        got += n;
        if (n == 0) {
            break;
        }
    }
    return got;
}

int voicenotes_extract_tar_bz2(
    const char *archive_path,
    const char *dest_dir,
    const char **wanted_names,
    int wanted_count
) {
    if (!archive_path || !dest_dir || !wanted_names || wanted_count <= 0) {
        return -1;
    }
    if (ensure_dir(dest_dir) != 0) {
        return -2;
    }

    FILE *fp = fopen(archive_path, "rb");
    if (!fp) {
        return -3;
    }

    int bzerror = BZ_OK;
    BZFILE *bz = BZ2_bzReadOpen(&bzerror, fp, 0, 0, NULL, 0);
    if (!bz || bzerror != BZ_OK) {
        if (bz) {
            BZ2_bzReadClose(&bzerror, bz);
        }
        fclose(fp);
        return -4;
    }

    int extracted = 0;
    char header[kTarBlock];
    char *buffer = (char *)malloc(kReadChunk);
    if (!buffer) {
        BZ2_bzReadClose(&bzerror, bz);
        fclose(fp);
        return -5;
    }

    while (extracted < wanted_count) {
        int n = read_decompressed(bz, header, kTarBlock, &bzerror);
        if (n < kTarBlock) {
            break;
        }

        int empty = 1;
        for (int i = 0; i < kTarBlock; i++) {
            if (header[i] != 0) {
                empty = 0;
                break;
            }
        }
        if (empty) {
            break;
        }

        char name[101];
        memcpy(name, header, 100);
        name[100] = '\0';

        /* ustar prefix (offset 345, 155 bytes) */
        if (memcmp(header + 257, "ustar", 5) == 0 && header[345] != '\0') {
            char prefix[156];
            memcpy(prefix, header + 345, 155);
            prefix[155] = '\0';
            char combined[256];
            snprintf(combined, sizeof(combined), "%s/%s", prefix, name);
            strncpy(name, combined, sizeof(name) - 1);
            name[sizeof(name) - 1] = '\0';
        }

        unsigned long long size = parse_octal(header + 124, 12);
        char typeflag = header[156];

        int should_write = (typeflag == '0' || typeflag == '\0') &&
            name_wanted(name, wanted_names, wanted_count);

        FILE *out = NULL;
        char out_path[1024];
        if (should_write) {
            const char *base = strrchr(name, '/');
            base = base ? base + 1 : name;
            snprintf(out_path, sizeof(out_path), "%s/%s", dest_dir, base);
            out = fopen(out_path, "wb");
            if (!out) {
                free(buffer);
                BZ2_bzReadClose(&bzerror, bz);
                fclose(fp);
                return -6;
            }
        }

        unsigned long long remaining = size;
        while (remaining > 0) {
            int chunk = remaining > (unsigned long long)kReadChunk ? kReadChunk : (int)remaining;
            int got = read_decompressed(bz, buffer, chunk, &bzerror);
            if (got <= 0) {
                if (out) {
                    fclose(out);
                }
                free(buffer);
                BZ2_bzReadClose(&bzerror, bz);
                fclose(fp);
                return -7;
            }
            if (out) {
                if (fwrite(buffer, 1, (size_t)got, out) != (size_t)got) {
                    fclose(out);
                    free(buffer);
                    BZ2_bzReadClose(&bzerror, bz);
                    fclose(fp);
                    return -8;
                }
            }
            remaining -= (unsigned long long)got;
            if (bzerror == BZ_STREAM_END && remaining > 0) {
                if (out) {
                    fclose(out);
                }
                free(buffer);
                BZ2_bzReadClose(&bzerror, bz);
                fclose(fp);
                return -9;
            }
        }

        if (out) {
            fclose(out);
            extracted += 1;
        }

        /* Tar pads file contents to 512-byte blocks. */
        unsigned long long pad = (512 - (size % 512)) % 512;
        if (pad > 0) {
            char padbuf[512];
            if (read_decompressed(bz, padbuf, (int)pad, &bzerror) < (int)pad) {
                break;
            }
        }
    }

    free(buffer);
    BZ2_bzReadClose(&bzerror, bz);
    fclose(fp);
    return extracted == wanted_count ? 0 : -10;
}
