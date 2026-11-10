/* jyopen.c -- LD_PRELOAD logger: records open/fopen results for help-related paths.
 * Read-only diagnostic; the engine is not modified.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <string.h>
#include <errno.h>

typedef int (*open_fn)(const char *, int, ...);
typedef void *(*fopen_fn)(const char *, const char *);

static open_fn real_open;
static fopen_fn real_fopen;

static int interesting(const char *p)
{
    if (!p)
        return 0;
    if (strstr(p, "elp") || strstr(p, "ELP"))
        return 1;
    return 0;
}

static void jlog(const char *path, int ret, int err)
{
    char buf[512];
    int n = 0;
    const char *p;
    int fd;
    char num[64];
    int i;

    for (p = path; p && *p && n < 400; p++)
        buf[n++] = *p;
    buf[n++] = ' ';
    buf[n++] = '=';
    buf[n++] = ' ';

    i = 0;
    if (ret < 0) {
        num[i++] = '-';
    }
    {
        int v = ret < 0 ? -ret : ret;
        char tmp[16];
        int t = 0;
        if (v == 0) tmp[t++] = '0';
        while (v > 0) { tmp[t++] = '0' + (v % 10); v /= 10; }
        while (t > 0) num[i++] = tmp[--t];
    }
    num[i++] = ' ';
    num[i] = 0;
    for (p = num; *p && n < 430; p++) buf[n++] = *p;
    if (err) {
        const char *e = "ENOENT";
        if (err != 2) e = "OTHER";
        for (p = e; *p && n < 460; p++) buf[n++] = *p;
    }
    buf[n++] = '\n';

    fd = (int)syscall(56, "/tmp/jyopen.log", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0)
        return;
    syscall(64, fd, buf, n);
    syscall(57, fd);
}

int open(const char *path, int flags, ...)
{
    va_list ap;
    int mode = 0;
    int ret;
    int e;

    va_start(ap, flags);
    if (flags & O_CREAT)
        mode = va_arg(ap, int);
    va_end(ap);

    if (!real_open)
        real_open = (open_fn)dlsym(RTLD_NEXT, "open");
    if (!real_open)
        return -1;

    errno = 0;
    ret = real_open(path, flags, mode);
    e = errno;
    if (interesting(path))
        jlog(path, ret, ret < 0 ? e : 0);
    errno = e;
    return ret;
}

int open64(const char *path, int flags, ...)
{
    va_list ap;
    int mode = 0;
    int ret;
    int e;

    va_start(ap, flags);
    if (flags & O_CREAT)
        mode = va_arg(ap, int);
    va_end(ap);

    if (!real_open)
        real_open = (open_fn)dlsym(RTLD_NEXT, "open");
    if (!real_open)
        return -1;

    errno = 0;
    ret = real_open(path, flags, mode);
    e = errno;
    if (interesting(path))
        jlog(path, ret, ret < 0 ? e : 0);
    errno = e;
    return ret;
}

void *fopen(const char *path, const char *mode)
{
    void *ret;
    int e;

    if (!real_fopen)
        real_fopen = (fopen_fn)dlsym(RTLD_NEXT, "fopen");
    if (!real_fopen)
        return 0;

    errno = 0;
    ret = real_fopen(path, mode);
    e = errno;
    if (interesting(path))
        jlog(path, ret ? 1 : -1, ret ? 0 : e);
    errno = e;
    return ret;
}

void *fopen64(const char *path, const char *mode)
{
    return fopen(path, mode);
}
