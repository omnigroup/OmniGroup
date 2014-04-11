// Copyright 1997-2005, 2008, 2009-2014 Omni Development, Inc. All rights reserved.
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

OFRandomState *OFRandomStateDuplicate(OFRandomState *oldstate_)
{
    if (!oldstate_)
        return NULL;
    
    SFMTState *oldstate = (SFMTState *)oldstate_;
    SFMTState *newstate = calloc(sizeof(*newstate), 1);
    memcpy(newstate, oldstate, sizeof(*newstate));
    newstate->psfmt32 = &newstate->sfmt[0].u[0] + ( oldstate->psfmt32 - &oldstate->sfmt[0].u[0] );
#if !defined(BIG_ENDIAN64) || defined(ONLY64)
    newstate->psfmt64 = (uint64_t *)&newstate->sfmt[0].u[0] + ( oldstate->psfmt64 - (uint64_t *)&oldstate->sfmt[0].u[0] );
#endif

    return (OFRandomState *)newstate;
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

unsigned int OFRandomNextStateN(OFRandomState *state, unsigned int n)
{
    OBASSERT(n > 0);
    uint64_t uniform = gen_rand64((SFMTState *)state);
    if ( (n & (n-1)) == 0 ) {
        return (unsigned int)uniform & (n-1);
    } else {
        return (unsigned int)( uniform % n );
    }
}

// [0,1) with 53-bits resolution
double OFRandomNextStateDouble(OFRandomState *state)
{
    return to_res53(OFRandomNextState64(state)); // same as genrand_res53, but tries to pretend we have state
}

static void _withDefaultRandomState(void (^block)(OFRandomState *))
{
    // Serialize on a queue so that this shared state can be used conveniently w/o external locking.
    static OFRandomState *defaultRandomState = NULL;
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.omnigroup.OmniFoundation.OFRandom.DefaultState", DISPATCH_QUEUE_SERIAL);
        defaultRandomState = OFRandomStateCreate();
    });

    dispatch_sync(queue, ^{
        block(defaultRandomState);
    });
}


uint32_t OFRandomNext32(void)
{
    __block uint32_t result = 0;
    _withDefaultRandomState(^(OFRandomState *state){
        result = OFRandomNextState32(state);
    });
    return result;
}

uint64_t OFRandomNext64(void)
{
    __block uint64_t result = 0;
    _withDefaultRandomState(^(OFRandomState *state){
        result = OFRandomNextState64(state);
    });
    return result;
}

double OFRandomNextDouble(void)
{
    __block double result = 0;
    _withDefaultRandomState(^(OFRandomState *state){
        result = OFRandomNextStateDouble(state);
    });
    return result;
}

NSData *OFRandomStateCreateDataOfLength(OFRandomState *state, NSUInteger byteCount)
{
#if 0 // gen_rand_array version. This doesn't seem to work the way I expect. Passing 1 for the size parameter writes to more than sizeof(w128_t) bytes and corrupts heap. The advantage of gen_rand_array() is that it will use vector instructions if available. We don't currently call this enough to warrant debugging this.
    // Round up to a multiple of sizeof(w128_t)
    NSUInteger roundedByteCount = ((byteCount + sizeof(w128_t) - 1) & ~(sizeof(w128_t) - 1));
    OBASSERT((roundedByteCount % sizeof(w128_t)) == 0);
    OBASSERT(roundedByteCount >= byteCount);
    
    w128_t *buffer = (w128_t *)malloc(roundedByteCount);
    NSUInteger wordCount = roundedByteCount / sizeof(w128_t);
    OBASSERT(wordCount <= INT_MAX); // SFMT takes int here.
    
    gen_rand_array((SFMTState *)state, buffer, (int)wordCount);

    return [[NSData alloc] initWithBytesNoCopy:buffer length:byteCount];
#else
    // Round up to a multiple of sizeof(uint64_t).
    NSUInteger roundedByteCount = ((byteCount + sizeof(uint64_t) - 1) & ~(sizeof(uint64_t) - 1));
    OBASSERT((roundedByteCount % sizeof(uint64_t)) == 0);
    OBASSERT(roundedByteCount >= byteCount);
    
    uint64_t *buffer = (uint64_t *)malloc(roundedByteCount);
    NSUInteger wordCount = roundedByteCount / sizeof(uint64_t);
    for (NSUInteger wordIndex = 0; wordIndex < wordCount; wordIndex++)
        buffer[wordIndex] = OFRandomNextState64(state);
    
    return [[NSData alloc] initWithBytesNoCopy:buffer length:byteCount];
#endif
}

NSData *OFRandomCreateDataOfLength(NSUInteger byteCount)
{
    __block NSData *result = nil;
    _withDefaultRandomState(^(OFRandomState *state){
        result = OFRandomStateCreateDataOfLength(state, byteCount);
    });
    return result;
}
