// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRandom.h>

#import <OmniBase/system.h>
#import <inttypes.h> // For PRIu8

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
static inline uint32_t _invert(uint32_t a, uint32_t p)
{
    uint32_t q, d;
    int32_t u, v, inv, t;

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
	fprintf(stderr, "Cannot invert %"PRIu8" mod p", a);
    }

    OBPOSTCONDITION(inv != 0 && inv != 1);
    return (inv);
}

/* Modular Multiplication: Decomposition method (from L'Ecuyer & Cote) */
static inline uint32_t _mult_mod(uint32_t a, uint32_t s, uint32_t m)
{
    uint32_t                        H, a0, a1, q, qh, rh, k, p;


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
static const uint32_t nRand = 4;
static float gaussAdd, gaussFac;
static BOOL  gaussInitialized = NO;

void OFRandomSeed(OFRandomState *state, uint32_t y)
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
uint32_t OFRandomGenerateRandomSeed(void)
{
    uint32_t seed;
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
        uint32_t seedSize, intervalSize;

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

    // Make sure the returned seed meets the needs of the implementation (>= 2 and < MERSENNE_PRIME_31).
    while (seed >= MERSENNE_PRIME_31)
        seed -= MERSENNE_PRIME_31;
    if (seed >= 2)
        return seed;
    return OFRandomGenerateRandomSeed(); // try again.
}

/*"
Returns an unsigned number between 0 and OF_RANDOM_MAX.  Note that the function does NOT return a number up to UINT_MAX (0xffffffff).
"*/
uint32_t OFRandomNextState(OFRandomState *state)
{
    OBPRECONDITION(state->y >= 2);

    if (state->y < 2) {
        OBASSERT_NOT_REACHED("Degenerate state?");
        OFRandomSeed(state, OFRandomGenerateRandomSeed());
        OBASSERT(state->y >= 2);
    }
    
    // We need to find IMP_A * invY + IMP_B mod M

    uint32_t old = state->y;
    uint32_t invY = _invert(old, MERSENNE_PRIME_31);

    uint32_t tmp = _mult_mod(IMP_A, invY, MERSENNE_PRIME_31);

    state->y = tmp + IMP_B;

    if (state->y >= MERSENNE_PRIME_31)
	state->y -= MERSENNE_PRIME_31;

    OBPOSTCONDITION(state->y >= 2);
    OBPOSTCONDITION(old <= OF_RANDOM_MAX);

    return (old);
}

uint32_t OFRandomNext(void)
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
    uint32_t i;
    float sum;
    
    i = nRand;
    sum = 0.0f;
    while (i--)
        sum += OFRandomNextState(state);

    return gaussFac * sum - gaussAdd;
}
