// xz_config.h - hand-generated config file to include XZ-Embedded into OmniFoundation.

#define XZ_DEC_BCJ
#define XZ_DEC_X86
#define XZ_EXTERN OB_HIDDEN

#include <stdbool.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include "xz.h"

#include <libkern/OSByteOrder.h>

/* Linux kernelisms */

#define min_t(t, a, b) ({ t a__ = (a); t b__ = (b); a__ > b__ ? b__ : a__; })
#define min(a, b) ({ typeof(a) a__ = (a); typeof(b) b__ = (b); a__ > b__ ? b__ : a__; })

#define __always_inline __inline__

#define kmalloc(sz, flags)		malloc(sz)
#define kfree(p)			free(p)

#define vmalloc(sz)			malloc(sz)
#define vfree(p)			free(p)

#define memzero(ptr, sz)		bzero(ptr, sz)
#define memeq(p1, p2, sz)		(bcmp(p1, p2, sz) == 0)

#define get_unaligned_le32(p)		OSReadLittleInt32(p, 0)
#define get_le32(p)			OSReadLittleInt32(p, 0)
#define put_unaligned_le32(val, p)	OSWriteLittleInt32(p, 0, val)
#define put_le32(val, p)		OSWriteLittleInt32(p, 0, val)
