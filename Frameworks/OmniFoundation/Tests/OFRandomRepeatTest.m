// Copyright 2009-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRandom.h>

RCS_ID("$Id$")

#if 0
// Two independent seed version

int main(int argc, char *argv[])
{
    OFRandomState *s0 = OFRandomStateCreateWithSeed32(OFRandomGenerateRandomSeed());
    OFRandomState *s1 = OFRandomStateCreateWithSeed32(OFRandomGenerateRandomSeed());

    // TODO: Add a way to print the internal state
    //fprintf(stderr, "seed0 %u\n", s0.y);
    //fprintf(stderr, "seed1 %u\n", s1.y);

    if (argc != 2) {
        fprintf(stderr, "usage: %s count\n", argv[0]);
        return 1;
    }
    
    long testIndex, testLimit = strtol(argv[1], NULL, 0);

    for (testIndex = 0; testIndex < testLimit; testIndex++) {
        uint32_t v0 = OFRandomNextState32(s0);
        uint32_t v1 = OFRandomNextState32(s1);
        uint64_t v = (((uint64_t)v0) << 32) | v1;
        
        printf("%qx\n", v);
    }

    OFRandomStateDestroy(s0);
    OFRandomStateDestroy(s1);

    return 0;
}
#endif

#if 0
// Single seed (busted) version
int main(int argc, char *argv[])
{
    OFRandomState s;
    OFRandomSeed(&s, OFRandomGenerateRandomSeed());
    
    fprintf(stderr, "seed %u\n", s.y);
    
    if (argc != 2) {
        fprintf(stderr, "usage: %s count\n", argv[0]);
        return 1;
    }
    
    long testIndex, testLimit = strtol(argv[1], NULL, 0);
    
    for (testIndex = 0; testIndex < testLimit; testIndex++) {
        uint32_t v0 = OFRandomNextState(&s);
        uint32_t v1 = OFRandomNextState(&s);
        uint64_t v = (((uint64_t)v0) << 32) | v1;
        
        printf("%qx\n", v);
    }
    
    return 0;
}
#endif

#if 1
// Single seed w/64-bit output
int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s count\n", argv[0]);
        return 1;
    }
    
    OFRandomState *s = OFRandomStateCreate();
    fprintf(stderr, "seed ???\n");

    long testIndex, testLimit = strtol(argv[1], NULL, 0);
    
    for (testIndex = 0; testIndex < testLimit; testIndex++) {
        uint64_t v = OFRandomNextState64(s);
        
        printf("%qx\n", v);
    }
    
    OFRandomStateDestroy(s);

    return 0;
}
#endif
