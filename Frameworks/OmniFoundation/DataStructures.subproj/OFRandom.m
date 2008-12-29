// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRandom.h>

#import <OmniBase/system.h>

RCS_ID("$Id$")


/* This is an nonlinear congruential generator, see
   http://random.mat.sbg.ac.at/ftp/pub/publications/weinga/diplom/
   for a complete discussion of these.  Presumably, this one would
   be termed an inverse nonlinear congruential generator since it
   uses inverses modulo M.

   Discussion of the choices of the constants can be seen at 
   http://random.mat.sbg.ac.at/ftp/pub/publications/peter/imp/
*/

#define MERSENNE_PRIME_31 (2147483647)  /* 2^31 - 1 */

/* These are the 13th set of constants from pg 19 of the IMP paper above */
#define IMP_A             (16643900)
#define IMP_B             (480227068)

/* Uses Euclids algorithm to find x such that ax = 1 mod p where p is prime */
static inline unsigned long _invert(unsigned long a, unsigned long p)
{
    unsigned long               q, d;
    long                        u, v, inv, t;

    OBPRECONDITION(a != 0 && a != 1);

    d = p;
    inv = 0;
    v = 1;
    u = a;

    do {
	q = d / u;
	t = d % u;
	d = u;
	u = t;
	t = inv - q * v;
	inv = v;
	v = t;
    } while (u != 0);

    if (inv < 0)
	inv += p;

    if (d != 1) {
	/* This should never happen, really */
	fprintf(stderr, "Cannot invert %ld mod p", a);
    }

    OBPOSTCONDITION(inv != 0 && inv != 1);
    return (inv);
}

/* Modular Multiplication: Decomposition method (from L'Ecuyer & Cote) */
static inline unsigned long _mult_mod(unsigned long a, unsigned long s, unsigned long m)
{
    unsigned long                        H, a0, a1, q, qh, rh, k, p;


    H = 32768;			/* 2 ^ 15  for 32 bit basetypes. */

    if (a < H) {
	a0 = a;
	p = 0;
    } else {
	a1 = a / H;
	a0 = a - H * a1;
	qh = m / H;
	rh = m - H * qh;
	if (a1 >= H) {
	    a1 = a1 - H;
	    k = s / qh;
	    p = H * (s - k * qh) - k * rh;
	    while (p < 0)
		p += m;
	} else
	    p = 0;

	if (a1 != 0) {
	    q = m / a1;
	    k = s / q;
	    p = p - k * (m - a1 * q);
	    if (p > 0)
		p -= m;
	    p = p + a1 * (s - k * q);
	    while (p < 0)
		p += m;
	}
	k = p / qh;
	p = H * (p - k * qh) - k * rh;
	while (p < 0)
	    p += m;
    }
    if (a0 != 0) {
	q = m / a0;
	k = s / q;
	p = p - k * (m - a0 * q);
	if (p > 0)
	    p -= m;
	p = p + a0 * (s - k * q);
	while (p < 0)
	    p += m;
    }
    return (p);
}


float OFRandomMax = (float)INT_MAX;
static const unsigned int nRand = 4;
static float gaussAdd, gaussFac;
static BOOL  gaussInitialized = NO;

void OFRandomSeed(OFRandomState *state, unsigned long y)
{
    if (!gaussInitialized) {
        float aRand;

        // Set up values for gaussian random number generation
        aRand = powf(2, 31) - 1;
        gaussAdd = sqrtf(3 * nRand);
        gaussFac = 2 * gaussAdd / (nRand * aRand);
        gaussInitialized = YES;
    }
    
    state->y = y;
    OBPOSTCONDITION(state->y >= 2);
}

/*"
Generates a random seed value appropriate for supplying to OFRandomSeed. Attempts to use /dev/urandom for (presumably) the best randomness for the seed (doesn't use /dev/random as that can block and we wish not to block). If we can't use /dev/urandom for some reason, we fall back to generating a seed value using the clock.
 "*/
unsigned int OFRandomGenerateRandomSeed(void)
{
    unsigned int seed;
    BOOL haveSeed  = NO;
    FILE *urandomDevice;

    urandomDevice = fopen("/dev/urandom", "r");	// use /dev/urandom instead of /dev/random because the latter can block
    if (urandomDevice != NULL) {
        size_t readSize;

        readSize = fread(&seed, sizeof(seed), 1, urandomDevice);
        haveSeed = (readSize == 1);
        fclose(urandomDevice);
    }

    if (!haveSeed) {
        NSTimeInterval interval;
        char *seedp, *intervalp;
        unsigned int seedSize, intervalSize;

        seedp = (char *)&seed;
        seedSize = sizeof(seed);
        while (seedSize--) {
            *seedp = 0;

            interval = [NSDate timeIntervalSinceReferenceDate];
            intervalp = (char *)&interval;
            intervalSize = sizeof(interval);
            while (intervalSize--) {
                *seedp ^= *intervalp;
                intervalp++;
            }
            seedp++;
        }
    }

    return seed;
}

/*"
Returns an unsigned number between 0 and OF_RANDOM_MAX.  Note that the function does NOT return a number up to UINT_MAX (0xffffffff).
"*/
unsigned long OFRandomNextState(OFRandomState *state)
{
    unsigned long invY, tmp;
    unsigned long old;

    OBPRECONDITION(state->y >= 2);

    // We need to find IMP_A * invY + IMP_B mod M

    old = state->y;
    invY = _invert(old, MERSENNE_PRIME_31);

    tmp = _mult_mod(IMP_A, invY, MERSENNE_PRIME_31);

    state->y = tmp + IMP_B;

    if (state->y >= MERSENNE_PRIME_31)
	state->y -= MERSENNE_PRIME_31;

    OBPOSTCONDITION(state->y >= 2);
#warning TJW: Figure out why this sometimes fails.  Maybe some detail of my implementation of this algorithm is wrong
//    OBPOSTCONDITION(old <= OF_RANDOM_MAX);
    return (old);
}

unsigned long OFRandomNext(void)
{
    static OFRandomState defaultRandomState;
    static BOOL firstTime  = YES;

    if (firstTime) {
        // seed the default random state
        OFRandomSeed(&defaultRandomState, OFRandomGenerateRandomSeed());
        firstTime = NO;
    }
    return OFRandomNextState(&defaultRandomState);
}

float OFRandomGaussState(OFRandomState *state)
{
    unsigned int i;
    float sum;
    
    i = nRand;
    sum = 0.0f;
    while (i--)
        sum += OFRandomNextState(state);

    return gaussFac * sum - gaussAdd;
}
