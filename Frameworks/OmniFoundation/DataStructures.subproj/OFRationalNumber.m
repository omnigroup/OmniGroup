// Copyright 2005-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRationalNumber.h>

#import <OmniFoundation/NSNumber-OFExtensions.h>

RCS_ID("$Id$");

typedef long long ofr_signed_wide;
typedef unsigned long long ofr_unsigned_wide;
#define OFR_WORKING_WIDTH (unsigned int)(CHAR_BIT * sizeof(ofr_signed_wide) - 1)
#define OFR_WORKING_MAX (ofr_signed_wide)((UINTMAX_C(1) << OFR_WORKING_WIDTH) - 1)
#define OFR_DENOMINATOR_WIDTH (OFR_WORKING_WIDTH/2) /* A product must fit in an ofr_signed_wide */
#define OFR_DENOMINATOR_MAX (ofr_component)( (INTMAX_C(1) << OFR_DENOMINATOR_WIDTH) - 1 )

static void OFRationalFromParts(struct OFRationalNumberStruct *r, ofr_unsigned_wide numerator, ofr_unsigned_wide denominator, BOOL negative);
static void OFRationalFromPartsExp(struct OFRationalNumberStruct *r, ofr_unsigned_wide numerator, ofr_unsigned_wide denominator, int exponent, BOOL negative);
static BOOL OFRationalFromStringScanner(NSScanner *scan, struct OFRationalNumberStruct *n);

struct OFRationalNumberStruct OFRationalFromRatio(int numerator, int denominator)
{
    struct OFRationalNumberStruct rn = OFRationalZero;  // initialize rn.lop, etc.
    OFRationalFromParts(&rn,
			(numerator < 0 ? -numerator : numerator),
			(denominator < 0 ? -denominator : denominator),
			(numerator < 0 && denominator > 0) || (denominator < 0 && numerator > 0));
    return rn;
}

struct OFRationalNumberStruct OFRationalFromDouble(double d)
{
    if (d == 0)
        return OFRationalZero;

    int exponent;
    int mbits;
    ofr_unsigned_wide m;
    struct OFRationalNumberStruct r;
    
    r.lop = 0;
    mbits = MIN(DBL_MANT_DIG, CHAR_BIT*(int)sizeof(m));
    m = ldexp(frexp(fabs(d), &exponent), mbits);
    OFRationalFromPartsExp(&r, m, 1, exponent - mbits, d<0);
    
    /*  Properly set the loss of precision bit when converting from a double. Right now it gets set in some cases even if converting the rational back to a double would produce the same number, because we had to round in order to fit the denominator: OFRationalFromDouble( 0.01 ) gets the lop bit set, even though it comes out as 1/100. But OFRationalFromDouble(nextafter(0.01, 1)) *should* get the lop bit set, because it also comes out as 1/100. */
    
    if (r.lop) {
        double rebuilt = (double)r.numerator / (double)r.denominator;
        // This is one of those rare cases where exact floating-point equality *is* the desired behavior
        // NSLog(@"OFRationalFromDouble: %g - %g = %g  (%a - %a = %a)", rebuilt, fabs(d), rebuilt - fabs(d), rebuilt, fabs(d), rebuilt - fabs(d));
        if (rebuilt == fabs(d))
            r.lop = 0;
    }
    
    return r;
}

struct OFRationalNumberStruct OFRationalFromLong(long l)
{
    struct OFRationalNumberStruct r;
    r.lop = 0;
    if(l < 0) {
        l = -l;
        r.negative = 1;
    } else if (l == 0) {
        return OFRationalZero;
    } else {
        r.negative = 0;
    }
    OFRationalFromParts(&r, l, 1, r.negative);
    return r;
}

double OFRationalToDouble(struct OFRationalNumberStruct v)
{
    double d = (double)(v.numerator) / (double)(v.denominator);
    return (v.negative? -d : d);
}

// long OFRationalToLong(struct OFRationalNumberStruct v);


/*
 The extended version of Euclid's algorithm, returning the multiplicative inverse of n mod m (and discarding the GCD, which had better be 1 for this to work anyway).
 */
static void ofr_ext_euclid(long long n, long long m, long long *result)
{
    long long n0, m0, n1, m1, n2, m2;
    
    // Triplets  N=<n0,n1,n2>  and M=<m0,m1,m2>
    // Start out with N=<n,1,0> and M=<m,0,1>
    // We will form linear combinations of these, N'=?*N+?*M and M'=?*N+?*M
    // which means that the invariant that for any triplet <a,b,c>  a = n*b + m*c will remain

    if (n > m) {
        n0 = n; n1 = 1; n2 = 0;
        m0 = m; m1 = 0; m2 = 1;
    } else {
        n0 = m; n1 = 0; n2 = 1;
        m0 = n; m1 = 1; m2 = 0;
    }    
    
    for(;;) {
        assert(n0 > m0);
        
        if (m0 == 1) {
            /* if m0==1, then by the invariant, 1==n*m1 + m*m2, so m1 and m2 are multiplicative inverses of the initial n,m resp. mod m,n*/
            /* either m1 or m2 is presumably negative */
            result[0] = m1;
            result[1] = m2;
            return;
        }

        lldiv_t d = lldiv(n0, m0);
        if (d.rem == 0) {
            /* Uh oh: the gcd is in m0, but it's not equal to 1. Fail! */
            OBASSERT_NOT_REACHED("ofr_minv_euclid: args not coprime");
            result[0] = 0;
            result[1] = 0;
            return;
        }

        // Set N = N - q * M, then swap N and M to keep n > m
        long long x0, x1, x2;
        x1 =    n1 - d.quot * m1;
        x2 =    n2 - d.quot * m2;
        x0 = /* n0 - d.quot * m0 */ d.rem;   // d.quot * m0 + d.rem = n0
        
        OBINVARIANT(x0 == x1 * n + x2 * m);
        
        n0 = m0; n1 = m1; n2 = m2;
        m0 = x0; m1 = x1; m2 = x2;
    }
}

#if 0
static unsigned long ofr_gcd_euclid(unsigned long n, unsigned long m)
{
    /*
     Finds greatest divisor, d, of n and m:   n%d==0, m%d==0
     Restate that as:  n=n'*d, m=m'*d for some n', m',d; find d
     Note that if you have any numbers q,r such that q*m+r=n, then q*m+r=n'd --> r=(n'-q*m')d
     */
    
    if (n < m) {
        unsigned long t = n;
        n = m;
        m = t;
    }
    for(;;) {
        assert (n >= m);
        unsigned long r = n % m;
        if (r == 0)
            return m;  /* n is a multiple of m */
        n = m;
        m = r;
    }
}

#else

/*
 
This is a machine-efficient version of Euclid's gcd algorithm.

It takes advantage of the fact that it's not necessary to use modulus in the normal Euclid's algorithm; as long as you subtract *any* multiple of the smaller number from the larger number, it's valid. To complete the algorithm with the fewest iterations, you want to subtract the largest multiple possible, which means taking the remainder (n mod m). But here, we subtract only one multiple. As a result, the algorithm will take more iterations to finish, but each iteration should be much faster since there's no remainder operation. I haven't actually timed the performance of each of these, though...

Thanks to cut-the-knot.org, which credits the algorithm to R. Silver and J. Tersian (via Knuth, of course...).

*/
static ofr_unsigned_wide ofr_gcd_odd(ofr_unsigned_wide n, ofr_unsigned_wide m)
{
    OBPRECONDITION( (n&m&1) == 1 );  // both n and m must be odd (caller takes care of factors of two)
        
    for(;;) {
        /* n and m are both odd, but we don't know which is larger */
        if (n < m) {
            ofr_unsigned_wide t = n;
            n = m;
            m = t;
        }

        /* Assume n > m, and n and m both odd. subtract a multiple of the smaller number from the larger number. */
        n -= m;
        
        if (n == 0)
            break;  /* divisor is left in m */
        
        /* n is even (it's the difference between two odd numbers), but m is still odd; we can pull out factors of 2 */
        do {
            n >>= 1;
        } while((n&1) == 0);
        
        /* both are odd, so we can return to top of loop */
    }

    return m;
}

static ofr_unsigned_wide ofr_gcd(ofr_unsigned_wide n, ofr_unsigned_wide m)
{
    int shift = 0;
    while((n&1) == 0 && (m&1) == 0) {
        shift += 1;
        n >>= 1;
        m >>= 1;
    }
    
    while((n&1) == 0)
        n>>=1;
    while((m&1) == 0)
        m>>=1;
    
    return ofr_gcd_odd(n, m) << shift;    
}

#endif

/*
 Call the "size" of a fraction p/q the magnitude of the larger of p or q: so that the size of 1/3 is 3, of 5/2 is 5, etc. Given a rational number, we want to find the nearest rational number whose size is smaller than some specified number (less than 2^31, for example, to fit in a machine word).
 
 A Farey sequence (named after J Farey, 1766-1826, although proofs of its interesting properties are actually due to C. Haros and to Cauchy) is the ordered sequence of all fractions, p/q, in lowest form (p and q are relatively prime), where q is less than some number; that is, the sequence of all  rationals between 0 and 1 below a given size. This can be easily extended to allow rationals greater than 1 (up to 1/0) without changing the math.
 Farey sequences have a couple of interesting properties:
   - Given any three consecutive members of the sequence, the middle term is the mediant of its neighbors (the mediant of a/b and c/d is (a+c)/(b+d) )
   - Given any two consecutive terms, a/b and c/d, then  b*c - a*d = 1
 
 If we have a number N=p/q, 0<N<1, q>1, of size S=q, then we can choose the Farey sequence for that size. Then its neighbors in that sequence will necessarily have smaller denominators than S, and they can be easily computed using the two relations above. Call this the "neighbors" algorithm:
   neighbors(p/q) --> (p_left/q_left, p_right/q_right), where:
     p_left/q_left , p/q , p_right/q_right   are consecutive members of a Farey sequence for size(q)
     Therefore the 'left' and 'right' fractions both have size less than that of p/q, and they are the closest fractions whose sizes are less than p/q.
 
 ofr_reduce() repeatedly applies the neighbors algorithm in order to find the two fractions closest to p/q below a specified size. At each step, it maintains two fractions (call them L and R), one less than p/q and one greater than p/q, both with the property that there is no smaller fraction between them and p/q.
   - Therefore, L and R are consecutive members of a Farey series (F(n) where n < size(p/q)). Therefore:
     - If size(L)<size(R), then neighbors(R) will produce L' and R' where L' = L
     - Likewise for size(L)>size(R).
     - Repeated application of neighbors() to the larger of L and R will eventually produce values for L and R which are both of sufficiently small size and which are in fact the nearest rationals to p/q which are satisfactorily small. The invariant L<p/q<R will hold at each step.
   - Call this "algorithm A".

 The question now is whether to choose L or R when rounding a number. An obvious choice is to choose the one that is numerically closer to the original number. Knuth (_Art_, vol 2) says that it's actually better to round off according to the mediant: that is, if p/q > mediant(L,R) then choose R, if it's less than the mediant then choose L. This is for numerical reasons when doing long computations. We generally don't care about that, but we might as well do it the right way anyway.
 Since neighbors(X) produces two numbers whose mediant is X, then we conveniently have mediants available for comparison. The last step of alg. A produces L and R whose mediant is either the previous value of L ( < p/q ) or the previous value of R ( > p/q ), in which case the mediant-cut algorithm indicates that we should use R or L (respectively) for the final value.
 Note that we end up using the value that is *not* the one that was replaced by the most recent call to neighbors(). This means we don't actually need to copmute the result of that invocation of neighbors(). In fact, we can terminate the whole algorithm easrly, and just use whichever of L or R becomes satisfactorily small soonest.
 This is one of those rare coincidences in which the obvious greedy algorithm also produces the correct result. I'm going to go celebrate!  [wim nov05]
*/

static void ofr_reduce(ofr_unsigned_wide *p_, ofr_unsigned_wide *q_, ofr_signed_wide maxp, ofr_signed_wide maxq)
{
    ofr_signed_wide p, pl, pr, q, ql, qr;
        
    p = *p_;
    q = *q_;
    
    OBPRECONDITION(ofr_gcd(p,q) == 1);
    
    if (maxq < 1)
        maxq = 1;
    if (maxp < 1)
        maxp = 1;
    
    if (p <= maxp && q <= maxq)
        return;
    
    for(;;) {
        /* neighbors algorithm: generate pl/ql and pr/qr; ql*p - pl*q == 1, etc. */
        {
            ofr_signed_wide inv[2];
            ofr_ext_euclid(p, q, inv); // --> inv[0] * p + inv[1] * q == 1, but inv may be < 0
            if (inv[0] > 0) {
                OBASSERT(inv[0] < q);
                OBASSERT(inv[1] < 0);
                ql = inv[0];
                qr = q - inv[0];
                pl = - inv[1];
                pr = p + inv[1];
            } else {
                OBASSERT(inv[0] < 0);
                OBASSERT(inv[1] > 0);
                OBASSERT(inv[1] < p);
                ql = q + inv[0];
                qr = - inv[0];
                pl = p - inv[1];
                pr = inv[1];
            }
        }
        //NSLog(@"%llu/%llu -> %llu/%llu  %llu/%llu", p, q, pl, ql, pr, qr);
        OBINVARIANT( ql*p - pl*q == 1 );
        OBINVARIANT( q*pr - p*qr == 1 );
        OBINVARIANT( p == pl+pr );
        OBINVARIANT( q == ql+qr );
        
#ifdef FAREY_TEST
        printf("\t%ld/%ld  --   %ld/%ld   --  %ld/%ld\n", pl, ql, p, q, pr, qr);
#endif
        
        if ((pl <= maxp && ql <= maxq) || (pr <= maxp && qr <= maxq)) {
            if (ql < qr) {
                *q_ = ql;
                *p_ = pl;
            } else {
                *q_ = qr;
                *p_ = pr;
            }
            return;
        }
        
        if (ql > qr) {
            p = pr;
            q = qr;
        } else {
            p = pl;
            q = ql;
        }
    }
}

static void OFRationalFromParts(struct OFRationalNumberStruct *r, ofr_unsigned_wide numerator, ofr_unsigned_wide denominator, BOOL negative)
{
    OFRationalFromPartsExp(r, numerator, denominator, 0, negative);
}

static unsigned int ofr_width(ofr_unsigned_wide n)
{
    OBASSERT(n >= 0);
    unsigned int shift = 0;
    
    for(;;) {
        if (n < INT_MAX)
            return shift + ffs((int)n);
        n >>= ( CHAR_BIT * sizeof(int) );
        shift += (unsigned int)( CHAR_BIT * sizeof(int) );
    }
}

static BOOL OFRationalSpecialCases(struct OFRationalNumberStruct *r, ofr_unsigned_wide numerator, ofr_unsigned_wide denominator, BOOL negative)
{
    if (numerator == 0) {
        r->numerator = 0;
        r->denominator = 0;
        r->negative = (r->lop && negative)?1:0;   // Only approximate zeroes can be negative
        return YES;
    }
    
    if (denominator == 0) {
        /* Ugh, there's not much we can do here. */
        r->numerator = ( numerator > OFR_DENOMINATOR_MAX )? OFR_DENOMINATOR_MAX : (ofr_component)numerator;
        r->denominator = 0;
        r->negative = negative? 1:0;
        r->lop = 1;
        return YES;
    }
    
    return NO;
}

static void OFRationalFromPartsExp(struct OFRationalNumberStruct *r, ofr_unsigned_wide numerator, ofr_unsigned_wide denominator, int exponent, BOOL negative)
{
    //NSLog(@"OFRationalFromPartsExp(%lld, %lld, %d, %s)", numerator, denominator, exponent, negative?"neg":"pos");
    if (numerator < 0) {
        numerator = -numerator;
        negative = !negative;
    }
    if (denominator < 0) {
        denominator = -denominator;
        negative = !negative;
    }

    if (OFRationalSpecialCases(r, numerator, denominator, negative))
        return;
    
    while((numerator & 1) == 0) {
        numerator >>= 1;
        exponent ++;
    }
    while((denominator & 1) == 0) {
        denominator >>= 1;
        exponent --;
    }
    
    ofr_unsigned_wide d = ofr_gcd_odd(numerator, denominator);
    
    numerator /= d;
    denominator /= d;
    
    while(exponent != 0 || numerator > OFR_DENOMINATOR_MAX || denominator > OFR_DENOMINATOR_MAX) {
        unsigned int numeratorWidth, denominatorWidth;
        numeratorWidth = ofr_width(numerator);
        denominatorWidth = ofr_width(denominator);
        //NSLog(@"Possibly reducing: n=%lld(%d) d=%lld(%d) exp=%d", numerator, numeratorWidth, denominator, denominatorWidth, exponent);
        if (exponent > 0) {
            unsigned shift = MIN((unsigned)exponent, numeratorWidth - OFR_WORKING_WIDTH);
            numerator <<= shift;
            exponent -= shift;
        } else {
            unsigned shift = MIN((unsigned)-exponent, denominatorWidth - OFR_WORKING_WIDTH);
            denominator <<= shift;
            exponent += shift;
        }
        if(exponent == 0 && numerator <= OFR_DENOMINATOR_MAX && denominator <= OFR_DENOMINATOR_MAX)
            break;
        
        r->lop = 1;
        ofr_reduce(&numerator, &denominator, OFR_DENOMINATOR_MAX, OFR_DENOMINATOR_MAX);
        
        if (OFRationalSpecialCases(r, numerator, denominator, negative))
            return;
    }
    
    /* We know that both the numerator and the denominator are <= OFR_DENOMINATOR_MAX (that's the termination condition of the above loop), so this cast is safe. */
    r->numerator = (ofr_component)numerator;
    r->denominator = (ofr_component)denominator;
    r->negative = negative?1:0;
    /* r->lop is unchanged */
}

void OFRationalMAdd(struct OFRationalNumberStruct *a, struct OFRationalNumberStruct b, int c)
{
    ofr_unsigned_wide d, xa, xb;
    BOOL differencing;
    BOOL negate;
    
    // a->lop may be nonzero
    if (c != 0 && b.lop != 0)
        a->lop = 1;

    if (b.numerator == 0 || c == 0) {
        return;
    }
    
    /* Normalize signs. We're either computing the sum or the difference of the magnitudes, and we're returning either the positive or the negative result. */
    if (a->negative) {
        if ( (b.negative && c > 0) || (!b.negative && c < 0) ) {
            differencing = NO;
            negate = YES;
        } else {
            differencing = YES;
            negate = YES;
        }
    } else {
        if ( (b.negative && c > 0) || (!b.negative && c < 0) ) {
            differencing = YES;
            negate = NO;
        } else {
            differencing = NO;
            negate = NO;
        }
    }
    if (c < 0)
        c = -c;
    
    if (a->numerator == 0) {
        OBASSERT(!negate);
        OFRationalFromParts(a, b.numerator * c, b.denominator, differencing);
        return;
    }
    
    d = ofr_gcd(a->denominator, b.denominator);
    xa = a->denominator / d;
    xb = b.denominator / d;
    // TODO: Overflow / loss-of-precision
    
    ofr_unsigned_wide m = a->denominator * xb;
    ofr_unsigned_wide left = a->numerator * xb;
    ofr_unsigned_wide right = b.numerator * xa * c;
    if (differencing) {
        if (left > right)
            left -= right;
        else {
            left = ( right - left );
            negate = !negate;
        }
    } else {
        left += right;
    }
    
    OFRationalFromParts(a, left, m, negate);
}

BOOL OFRationalIsWellFormed(struct OFRationalNumberStruct n)
{
    if (n.denominator == 0) {
        return (n.numerator == 0);
    }
    
    if (n.numerator == 0) {
        if (n.denominator != 0)
            return NO;
        if (!n.lop && n.negative)
            return NO;
        return YES;
    }
    
    if (ofr_gcd(n.numerator, n.denominator) != 1)
        return NO;
    
    return YES;
}

struct OFRationalNumberStruct OFRationalMultiply(struct OFRationalNumberStruct a, struct OFRationalNumberStruct b)
{
    unsigned long crossl, crossr;
    
    if (a.numerator == 0 || b.numerator == 0) {
        struct OFRationalNumberStruct r = OFRationalZero;
        
        if ((a.numerator == 0 && !a.lop) || (b.numerator == 0 && !b.lop))
            r.lop = 0;
        else
            r.lop = ( a.lop || b.lop );
        
        return r;
    }
    
    crossl = (ofr_component)ofr_gcd(a.numerator, b.denominator);
    crossr = (ofr_component)ofr_gcd(a.denominator, b.numerator);
    if (crossl > 1) {
        a.numerator /= crossl;
        b.denominator /= crossl;
    }
    if (crossr > 1) {
        b.numerator /= crossr;
        a.denominator /= crossr;
    }
    
    // TODO: Overflow / loss-of-precision
    
    return (struct OFRationalNumberStruct){
        .numerator = a.numerator * b.numerator,
        .denominator = a.denominator * b.denominator,
        .negative = ( a.negative && !b.negative ) || ( !a.negative && b.negative ),
        .lop = ( a.lop || b.lop )
    };
}

struct OFRationalNumberStruct OFRationalInverse(struct OFRationalNumberStruct n)
{
    return (struct OFRationalNumberStruct){
        .numerator = n.denominator,
        .denominator = n.numerator,
        .lop = n.lop,
        .negative = n.negative
    };    
}

BOOL OFRationalIsEqual(struct OFRationalNumberStruct a, struct OFRationalNumberStruct b)
{
    if (a.numerator == b.numerator &&
        a.denominator == b.denominator &&
        a.negative == b.negative)
        return YES;
    else
        return NO;
}

NSComparisonResult OFRationalCompare(struct OFRationalNumberStruct a, struct OFRationalNumberStruct b)
{
    if (a.numerator == b.numerator &&
        a.denominator == b.denominator &&
        a.negative == b.negative)
        return NSOrderedSame;
    
    if (a.negative && !b.negative)
        return NSOrderedAscending;
    if (!a.negative && b.negative)
        return NSOrderedDescending;
    
    // TODO: Overflow

    unsigned long crossl = a.numerator * b.denominator;
    unsigned long crossr = b.numerator * a.denominator;
    
    if (crossl < crossr)
        return (a.negative)? NSOrderedDescending : NSOrderedAscending;
    else
        return (a.negative)? NSOrderedAscending : NSOrderedDescending;
}

NSString *OFRationalToStringForStorage(struct OFRationalNumberStruct a)
{
    if (a.numerator == 0) {
        return (a.lop)? @"~0" : @"0";
    }
    
    NSMutableString *buf = [[NSMutableString alloc] init];
    if (a.lop)
        [buf appendString:@"~"];
    if (a.negative)
        [buf appendString:@"-"];
    [buf appendFormat:@"%lu", a.numerator];
    if (a.denominator != 1)
        [buf appendFormat:@"/%lu", a.denominator];
    
    NSString *result = [buf copy];
    [buf release];
    return [result autorelease];
}

NSString *OFRationalToStringForLocale(struct OFRationalNumberStruct a, NSDictionary *dict)
{
    if (a.numerator == 0) {
        return (a.lop)? @"~0" : @"0";
    }
    
    NSString *buf;
    /* We use NSString's signed number format here in order to get the locale's desired sign behavior. This does mean that we'll produce an incorrect result for numbers with large numerators. */
    if (a.denominator == 1)
        buf = [[NSString alloc] initWithFormat:@"%ld" locale:dict, ( a.negative? -a.numerator : a.numerator )];
    else
        buf = [[NSString alloc] initWithFormat:@"%ld/%lu" locale:dict, ( a.negative? -a.numerator : a.numerator ), a.denominator];

    if (a.lop) {
        NSString *result = [@"~" stringByAppendingString:buf];
        [buf release];
        return result;
    } else {
        return [buf autorelease];
    }
}

BOOL OFRationalFromStringForStorage(NSString *s, struct OFRationalNumberStruct *n)
{    
    if ([NSString isEmptyString:s])
        return NO;
    
    NSScanner *scan = [[NSScanner alloc] initWithString:s];
    BOOL ok = OFRationalFromStringScanner(scan, n);
    if (![scan isAtEnd])
        ok = NO;
    [scan release];
    return ok;
}

static BOOL OFRationalFromStringScanner(NSScanner *scan, struct OFRationalNumberStruct *n)
{
    long long ll;
    ofr_unsigned_wide numerator, denominator;
    int exponent;
    BOOL negative;
    
    bzero((void *)n, sizeof(n));
    
    if ([scan scanString:@"~" intoString:NULL])
        n->lop = 1;
    else
        n->lop = 0;
    
    negative = [scan scanString:@"-" intoString:NULL];
    
    if (![scan scanLongLong:&ll])
        return NO;
    if (ll < 0) {
        negative = !negative;
        numerator = - ll;
    } else {
        numerator = ll;
    }
    if ([scan scanString:@"!" intoString:NULL]) {
        if (![scan scanInt:&exponent])
            return NO;
    } else {
        exponent = 0;
    }
    if ([scan scanString:@"/" intoString:NULL]) {
        if (![scan scanLongLong:&ll])
            return NO;
        if (ll < 0) {
            negative = !negative;
            denominator = - ll;
        } else {
            denominator = ll;
        }
    } else
        denominator = 1;
    OFRationalFromPartsExp(n, numerator, denominator, exponent, negative);    
    
    return YES;
}

void OFRationalRound(struct OFRationalNumberStruct *n, unsigned long max_denominator)
{
    if (max_denominator < 2)
        max_denominator = 1;
    
    ofr_unsigned_wide num = n->numerator;
    ofr_unsigned_wide den = n->denominator;
    
    ofr_reduce(&num, &den, OFR_DENOMINATOR_MAX, max_denominator);
    
    // TODO: We know that num/den are rel. prime, so we don't really need to use the full OFRationalFromParts here
    // NB: We know that num and den are less than or equal to OFR_DENOMINATOR_MAX, which is an unsigned long, so it's safe to cast them to unsigned long
    OFRationalFromParts(n, num, den, n->negative);
}

#ifdef FAREY_TEST

int main(int argc, char **argv) {
    if (argc != 3 && argc != 4) {
        printf("usage: %s numerator denominator [maxdenominator]\n", argv[0]);
    }
    
    long n = strtol(argv[1], NULL, 10);
    long d = strtol(argv[2], NULL, 10);
    long g = ofr_gcd(n,d);
    n /= g;
    d /= g;
    long maxd = ( argc == 4 ) ? strtol(argv[3], NULL, 10) : 1;
    double v0 = (double)n / (double)d;
    printf("initial value: %ld/%ld = %g\n", n, d, v0);
    
    ofr_reduce(&n, &d, maxd, maxd);
    
    double v1 = (double)n / (double)d;
    printf("final value: %ld/%ld = %g\n", n, d, v1);
    printf("difference: %g (%.2f)\n", fabs(v0-v1), fabs(v0-v1)/v0);
    
    return 0;
}

#endif

@implementation OFRationalNumber

// Note that we don't actually have to override -alloc and -allocWithZone: in order to avoid NSNumber's placeholder goo: it checks the receiving class and behaves normally (calling NSAllocateObject()) if it's not NSNumber.

- initWithBytes:(const void *)rat objCType:(const char *)typeEncoding;
{
    static const char * const rationalType = @encode(struct OFRationalNumberStruct);
    if (rationalType != typeEncoding && strcmp(rationalType, typeEncoding) != 0) {
        OBRejectInvalidCall(self, _cmd, @"objCType was \"%s\", expecting \"%s\"", typeEncoding, rationalType);
    }
    memcpy(&r, rat, sizeof(r));
    return self;
}

- (void)getValue:(void *)buf
{
    memcpy(buf, &r, sizeof(r));
}

- (const char *)objCType;
{
    return @encode(typeof(r));
}

- (struct OFRationalNumberStruct)rationalValue;
{
    return r;
}

- (BOOL)boolValue
{
    if (r.numerator == 0)
        return NO;
    else
        return YES;
}

/* To implement if it turns out to be useful:

(Most of the numeric calls will raise an NSInternalInconsistencyException if not overridden, complaining about the objCType we returned. This is as documented in the Foundation docs.)

- (char)charValue
- (short)shortValue
- (int)intValue
- (long)longValue
- (long long)longLongValue

- (unsigned char)unsignedCharValue
- (unsigned short)unsignedShortValue
- (unsigned int)unsignedIntValue
- (unsigned long)unsignedLongValue
- (unsigned long long)unsignedLongLongValue

- (NSDecimal)decimalValue;

- (NSString *)descriptionWithLocale:(NSDictionary *)locale;

*/

- (double)doubleValue
{
    return OFRationalToDouble(r);
}

- (float)floatValue
{
    return (float)OFRationalToDouble(r);
}

- (NSString *)stringValue
{
    return OFRationalToStringForStorage(r);
}

- (int)intValue
{
    return (int)OFRationalToDouble(r);
}

- (NSComparisonResult)compare:(NSNumber *)otherNumber
{
    if ([otherNumber isKindOfClass:[OFRationalNumber class]]) {
        struct OFRationalNumberStruct o = [(OFRationalNumber *)otherNumber rationalValue];
        return OFRationalCompare(r, o);
    } else {
        NSNumber *tmp = [[NSNumber alloc] initWithDouble:OFRationalToDouble(r)];
        NSComparisonResult result = [tmp compare:otherNumber];
        [tmp release];
        return result;
    }
}

- (BOOL)isEqualToNumber:(NSNumber *)otherNumber
{
    if ([otherNumber isKindOfClass:[OFRationalNumber class]]) {
        struct OFRationalNumberStruct o = [(OFRationalNumber *)otherNumber rationalValue];
        return OFRationalIsEqual(r, o);
    } else {
        return NO;
    }
}

- (BOOL)isExact
{
    return r.lop? NO : YES;
}

- descriptionWithLocale:(NSDictionary *)aLocale
{
    OBASSERT(strcmp(@encode(struct OFRationalNumberStruct), [self objCType]) == 0);

    if (aLocale == nil)
        return OFRationalToStringForStorage(r);
    else
        return OFRationalToStringForLocale(r, aLocale);
}

+ (NSNumber *)numberByPerformingOperation:(OFArithmeticOperation)op withNumber:(NSNumber *)v1 andNumber:(NSNumber *)v2
{
    if (v1 == nil || v2 == nil)
        OBRejectInvalidCall(self, _cmd, @"Numeric argument is nil");
    
    BOOL v1IsRational = [v1 isKindOfClass:[OFRationalNumber class]];
    BOOL v2IsRational = [v2 isKindOfClass:[OFRationalNumber class]];
    
    if (!v1IsRational && !v2IsRational && op != OFArithmeticOperation_Divide) {
        // Division is the only operation for which we'll promote two non-rationals to rationals. Otherwise, they stay integers (or whatever).
        return [super numberByPerformingOperation:op withNumber:v1 andNumber:v2];
    }

#define COMPUTE(into, arg1, arg2) \
    switch(op) { \
        case OFArithmeticOperation_Add:      into = arg1 + arg2; break; \
        case OFArithmeticOperation_Subtract: into = arg1 - arg2; break; \
        case OFArithmeticOperation_Multiply: into = arg1 * arg2; break; \
        case OFArithmeticOperation_Divide:   into = arg1 / arg2; break; \
        default: OBRejectInvalidCall(self, _cmd, @"Bad opcode %d", op); return nil; \
    }    
    
    if (![v1 isExact] || ![v2 isExact]) {
        // If either of our input values is inexact (a float, or a rational with the loss of precision flag), just treat them as doubles.
        double result;
        COMPUTE(result, [v1 doubleValue], [v2 doubleValue]);
        return [NSNumber numberWithDouble:result];
    }
    
    // We know that at least one number is a rational, and the other number (if not rational) is an exact type.
    struct OFRationalNumberStruct result;
    
    switch(op) {
        case OFArithmeticOperation_Add:
            result = [v1 rationalValue];
            OFRationalMAdd(&result, [v2 rationalValue], 1);
            break;
        case OFArithmeticOperation_Subtract:
            result = [v1 rationalValue];
            OFRationalMAdd(&result, [v2 rationalValue], -1);
            break;
        case OFArithmeticOperation_Multiply:
            result = OFRationalMultiply([v1 rationalValue], [v2 rationalValue]);
            break;
        case OFArithmeticOperation_Divide:
            result = OFRationalMultiply([v1 rationalValue], OFRationalInverse([v2 rationalValue]));
            break;
        default:
            OBRejectInvalidCall(self, _cmd, @"Bad opcode %d", op);
            return nil;
    }
    
    if (result.lop) {
        // We can't represent the result as an OFRational, so just use floating-point.
        double approximateResult;
        COMPUTE(approximateResult, [v1 doubleValue], [v2 doubleValue]);
        return [NSNumber numberWithDouble:approximateResult];
    }
    
    if (result.denominator == 1 && result.numerator < INT_MAX) {
        /* If it fits in an int, return it that way. */
        OBASSERT(!result.lop);
        return [NSNumber numberWithInteger: result.negative? -result.numerator : result.numerator];
    }
    
    return [NSNumber numberWithRatio:result];
}

@end

@implementation NSNumber (OFRationalNumberValue)

+ numberWithRatio:(struct OFRationalNumberStruct)r
{
    return [[[OFRationalNumber alloc] initWithBytes:&r objCType:@encode(struct OFRationalNumberStruct)] autorelease];
}

+ numberWithRatio:(int)numerator :(int)denominator
{
    return [self numberWithRatio:OFRationalFromRatio(numerator, denominator)];
}

- (struct OFRationalNumberStruct)rationalValue
{
    const char *t = [self objCType];
    
    if (t[0] && !t[1]) {
        switch(t[0]) {
            case _C_CHR:
            case _C_UCHR:
            case _C_SHT:
            case _C_USHT:
            case _C_INT:
            case _C_LNG:
                return OFRationalFromLong([self longValue]);
            case _C_UINT:
            case _C_ULNG:
            {
                struct OFRationalNumberStruct buf;
                unsigned long ulbuf;
                bzero(&buf, sizeof(buf));
                buf.lop = 0;
                ulbuf = [self unsignedLongValue];
                OFRationalFromParts(&buf, ulbuf, 1, 0);
                return buf;
            }
        }
    }
    
    return OFRationalFromDouble([self doubleValue]);
}

@end

