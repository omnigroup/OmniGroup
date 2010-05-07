// Copyright 1997-2005, 2008, 2009-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRandom.h>

#import <OmniBase/system.h>
#import <inttypes.h> // For PRIu8

RCS_ID("$Id$")

/*
 
 OFRandom is now a wrapper around the "SIMD-oriented Fast Mersenne Twister" from <http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/SFMT/index.html>
 
 When building it with 'make sse2' we get:
 
 gcc -O3 -finline-functions -fomit-frame-pointer -DNDEBUG -fno-strict-aliasing --param max-inline-insns-single=1800  -Wmissing-prototypes -Wall  -std=c99 -DMEXP=19937 -o test-std-M19937 test.c

 most of this is for speed, but we'll turn on the defines here and add -fno-strict-aliasing as a per-file compile option.
 
 Note that we do not export the float/batch generators. There are some comments in SFMT that you have to re-seed when switching generation methods and in fact we hit assertions if we might 32 and 64 generation.  So, we always generate 64 here and truncate to 32 if that's all the caller wanted.
 */
#ifndef DEBUG
    #define NDEBUG
#endif
#define MEXP 19937

// We also added this to make all the functions that would normally be extern be static.
#define OF_EMBEDDED

#include "../SFMT/SFMT.c"

/*
 Gathers several sources of random state, including some from /dev/urandom. If the entropy pool is low, though, that may not be great, so we gather some from the time.
 */
OFRandomState *OFRandomStateCreate(void)
{
    uint32_t seed[4];
    
    FILE *urandomDevice = fopen("/dev/urandom", "r");	// use /dev/urandom instead of /dev/random because the latter can block
    if (urandomDevice != NULL) {
        // 64-bits from urandom, to whatever extent it can provide it.
        fread(seed, sizeof(uint32_t), 2, urandomDevice);
        fclose(urandomDevice);
    }

    // 64-bits from the current time.
    CFAbsoluteTime ti = CFAbsoluteTimeGetCurrent();
    OBASSERT(sizeof(ti) == 2*sizeof(uint32_t));
    memcpy(&seed[2], &ti, sizeof(ti));
    
    return OFRandomStateCreateWithSeed32(seed, 4);
}

OFRandomState *OFRandomStateCreateWithSeed32(const uint32_t *seed, uint32_t count)
{
    SFMTState *state = SFMTStateCreate();
    init_by_array(state, seed, count);
    return (OFRandomState *)state;
}

void OFRandomStateDestroy(OFRandomState *state)
{
    SFMTStateDestroy((SFMTState *)state);
}

uint32_t OFRandomNextState32(OFRandomState *state)
{    
    // See the comment above; we only generate 64-bit values and truncate if only 32 were wanted.
    return (uint32_t)gen_rand64((SFMTState *)state);
}

uint64_t OFRandomNextState64(OFRandomState *state)
{
    return gen_rand64((SFMTState *)state);
}

// [0,1) with 53-bits resolution
double OFRandomNextStateDouble(OFRandomState *state)
{
    return to_res53(OFRandomNextState64(state)); // same as genrand_res53, but tries to pretend we have state
}

static OFRandomState *_OFDefaultRandomState(void)
{
    static OFRandomState *defaultRandomState = NULL;

    // seed the default random state
    if (!defaultRandomState)
        defaultRandomState = OFRandomStateCreate();
    
    return defaultRandomState;
}


// Shared state; not thread-safe!
uint32_t OFRandomNext32(void)
{
    return OFRandomNextState32(_OFDefaultRandomState());
}

uint64_t OFRandomNext64(void)
{
    return OFRandomNextState64(_OFDefaultRandomState());
}

double OFRandomNextDouble(void)
{
    return OFRandomNextStateDouble(_OFDefaultRandomState());
}
