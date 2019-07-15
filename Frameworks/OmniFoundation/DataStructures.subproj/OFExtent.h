// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <tgmath.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSGeometry.h>
#else
#import <CoreGraphics/CGGeometry.h>
#endif

#import <OmniBase/assertions.h>

// Like NSRange, but for CGFloats. For now we are assuming that length is non-negative; in the future it might be useful to have a right-aligned extents (max is the location not location + length).
typedef struct _OFExtent {
    CGFloat location;
    CGFloat length;
} OFExtent;

#define OFExtentZero (OFExtentMake(0.0f, 0.0f))

static inline OFExtent OFExtentMake(CGFloat location, CGFloat length)
{
    OBPRECONDITION(length >= 0.0);
    
    OFExtent e;
    e.location = location;
    e.length = length;
    return e;
}

static inline CGFloat OFExtentLocation(OFExtent e)
{
    return e.location;
}
static inline CGFloat OFExtentLength(OFExtent e)
{
    return e.length;
}

static inline CGFloat OFExtentMin(OFExtent e)
{
    OBPRECONDITION(e.length >= 0);
    return e.location;
}
static inline CGFloat OFExtentMid(OFExtent e)
{
    OBPRECONDITION(e.length >= 0);
    return (e.location + e.length / 2.0f);
}
static inline CGFloat OFExtentMax(OFExtent e)
{
    OBPRECONDITION(e.length >= 0);
    return e.location + e.length;
}

extern BOOL OFExtentsEqual(OFExtent a, OFExtent b);
extern NSString *OFExtentToString(OFExtent r);

static inline OFExtent OFExtentFromLocations(CGFloat p1, CGFloat p2)
{
    CGFloat min = MIN(p1, p2);
    CGFloat max = MAX(p1, p2);
    return OFExtentMake(min, max-min);
}

// Inclusive
static inline BOOL OFExtentContainsValue(OFExtent extent, CGFloat value)
{
    return (OFExtentMin(extent) <= value) && (value <= OFExtentMax(extent));
}

static inline BOOL OFExtentContainsExtent(OFExtent extent, OFExtent query)
{
    return OFExtentContainsValue(extent, OFExtentMin(query)) && OFExtentContainsValue(extent, OFExtentMax(query));
}

static inline CGFloat OFExtentClampValue(OFExtent extent, CGFloat value)
{
    if (value <= OFExtentMin(extent))
        return OFExtentMin(extent);
    if (value >= OFExtentMax(extent))
        return OFExtentMax(extent);
    return value;
}

// If you pass in two negative extents; this will return a positive one right now (i.e., location on the left)
static inline OFExtent OFExtentUnion(OFExtent a, OFExtent b)
{
    CGFloat min = MIN(OFExtentMin(a), OFExtentMin(b));
    CGFloat max = MAX(OFExtentMax(a), OFExtentMax(b));
    return OFExtentMake(min, max-min);
}

static inline OFExtent OFExtentIntersection(OFExtent a, OFExtent b)
{
    CGFloat start = MAX(OFExtentMin(a), OFExtentMin(b));
    CGFloat end = MIN(OFExtentMax(a), OFExtentMax(b));
    
    if (end < start)
        return OFExtentMake(0.0f,0.0f);
    else
        return OFExtentMake(start, end-start);
}


// Adds the delta to the minimum and subtracts it from the maximum. We currently allow negative extents, but this seems like a strange way to get one, so we currently asser that doesn't happen.
static inline OFExtent OFExtentInset(OFExtent a, CGFloat delta)
{
    if (a.length < delta*2)
        return OFExtentMake(OFExtentMid(a), 0.0f);
    
    CGFloat min = OFExtentMin(a) + delta;
    CGFloat max = OFExtentMax(a) - delta;
    OBASSERT(min <= max);
    return OFExtentMake(min, max-min);
}

// Returns a new extent with the same max, but an adjusted min point. We currently allow negative extents, but this seems like a strange way to get one, so we currently asser that doesn't happen.
static inline OFExtent OFExtentAdjustMin(OFExtent a, CGFloat delta)
{
    CGFloat min = OFExtentMin(a) + delta;
    CGFloat max = OFExtentMax(a);
    OBASSERT(min <= max);
    return OFExtentMake(min, max-min);
}

// Returns a new extent with the same min, but an adjusted max point. We currently allow negative extents, but this seems like a strange way to get one, so we currently asser that doesn't happen.
static inline OFExtent OFExtentAdjustMax(OFExtent a, CGFloat delta)
{
    CGFloat min = OFExtentMin(a);
    CGFloat max = OFExtentMax(a) + delta;
    OBASSERT(min <= max);
    return OFExtentMake(min, max-min);
}

// CGRect to OFExtent
static inline OFExtent OFExtentFromRectXRange(CGRect r)
{
    return OFExtentMake(CGRectGetMinX(r), CGRectGetWidth(r));
}
static inline OFExtent OFExtentFromRectYRange(CGRect r)
{
    return OFExtentMake(CGRectGetMinY(r), CGRectGetHeight(r));
}
static inline CGRect OFExtentsToRect(OFExtent xExtent, OFExtent yExtent)
{
    return CGRectMake(OFExtentMin(xExtent), OFExtentMin(yExtent),
                      OFExtentLength(xExtent), OFExtentLength(yExtent));
}

// Snaps the the smallest integral range that contains the extent.
static inline OFExtent OFExtentIntegral(OFExtent e)
{
    CGFloat min = (CGFloat)floor(OFExtentMin(e));
    CGFloat max = (CGFloat)ceil(OFExtentMax(e));
    return OFExtentMake(min, max-min);
}

static inline CGFloat OFExtentValueAtPercentage(OFExtent e, CGFloat p)
{
    return OFExtentMin(e) + p*OFExtentLength(e);
}

static inline CGFloat OFExtentPercentForValue(OFExtent e, CGFloat v)
{
    return (v - OFExtentMin(e)) / OFExtentLength(e);
}

// 
static inline OFExtent OFExtentAsNormalizedPoritionOfExtent(OFExtent toNormalize, OFExtent normalizeAgainst)
{
    CGFloat p1 = OFExtentPercentForValue(normalizeAgainst, OFExtentMin(toNormalize));
    CGFloat p2 = OFExtentPercentForValue(normalizeAgainst, OFExtentMax(toNormalize));

    OFExtent normalized = OFExtentFromLocations(p1, p2);
    
    return normalized;
}
                                                            
