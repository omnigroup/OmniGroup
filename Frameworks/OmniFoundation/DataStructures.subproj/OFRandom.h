// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFRandom.h 98221 2008-03-04 21:06:19Z kc $

#import <OmniFoundation/OFObject.h>

// Some platforms don't provide random number generation and of those that do, there are many different variants.  We provide a common random number generator rather than have to deal with each platform independently.  Additionally, we allow the user to maintain several random number generators.

typedef struct {
    unsigned long y; // current value any number between zero and M-1
} OFRandomState;

extern float OFRandomMax;

extern unsigned int OFRandomGenerateRandomSeed(void);	// returns a random number (generated from /dev/urandom if possible, otherwise generated via clock information) for use as a seed value for OFRandomSeed().
extern void OFRandomSeed(OFRandomState *state, unsigned long y);
extern unsigned long OFRandomNextState(OFRandomState *state);

extern unsigned long OFRandomNext(void);	// returns a random number generated using a default, shared random state.
extern float OFRandomGaussState(OFRandomState *state);

static inline float OFRandomFloat(OFRandomState *state)
/*.doc.
Returns a number in the range [0..1]
*/
{
    return (float)OFRandomNextState(state)/(float)OFRandomMax;
}

#define OF_RANDOM_MAX OFRandomMax // For backwards compatibility
