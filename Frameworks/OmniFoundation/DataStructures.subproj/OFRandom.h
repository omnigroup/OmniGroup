// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <stdint.h>

typedef struct _OFRandomState OFRandomState;

extern OFRandomState *OFRandomStateCreate(void); // Creates a state with a seed array based on /dev/urandom, the time and possibly other factors
extern OFRandomState *OFRandomStateCreateWithSeed32(const uint32_t *seed, uint32_t count);
extern OFRandomState *OFRandomStateDuplicate(OFRandomState *oldstate);
extern void OFRandomStateDestroy(OFRandomState *state);

extern uint32_t OFRandomNextState32(OFRandomState *state);
extern uint64_t OFRandomNextState64(OFRandomState *state);
extern unsigned int OFRandomNextStateN(OFRandomState *state, unsigned int n);
extern double OFRandomNextStateDouble(OFRandomState *state);

// Version that use a global shared state. Not thread-safe.
extern uint32_t OFRandomNext32(void);
extern uint64_t OFRandomNext64(void);
extern double OFRandomNextDouble(void);

extern NSData *OFRandomStateCreateDataOfLength(OFRandomState *state, NSUInteger byteCount) NS_RETURNS_RETAINED;
extern NSData *OFRandomCreateDataOfLength(NSUInteger byteCount) NS_RETURNS_RETAINED;
