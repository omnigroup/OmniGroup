// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/OFGeometry.h>

RCS_ID("$Id$");

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    #define NSStringFromPoint NSStringFromCGPoint
#endif

@interface OFGeometryTests :  OFTestCase
@end

@implementation OFGeometryTests

static CGFloat _randomCoord(OFRandomState *r)
{
    double t = OFRandomNextStateDouble(r); // 0..1
    return (CGFloat)(200 * t - 100); // -100 .. 100
}

static CGPoint _randomPoint(OFRandomState *r)
{
    return CGPointMake(_randomCoord(r), _randomCoord(r));
}

static CGPoint _deltaPoint(CGPoint a, CGPoint b)
{
    return CGPointMake(a.x - b.x, a.y - b.y);
}

static double _vectorLength(CGPoint v)
{
    return sqrt(v.x*v.x + v.y*v.y);
}

static double _distanceBetweenPoints(CGPoint a, CGPoint b)
{
    CGPoint d = _deltaPoint(a, b);
    return _vectorLength(d);
}

static CGPoint _normalizedVector(CGPoint v)
{
    double length = _vectorLength(v);
    return CGPointMake((CGFloat)(v.x/length), (CGFloat)(v.y/length));
}

static double _vectorDot(CGPoint v1, CGPoint v2)
{
    return v1.x * v2.x + v1.y * v2.y;
}

- (void)testCenterOfCircleFromThreePoints;
{
    OFRandomState *r = OFRandomStateCreate();
    const double minDistance = 1e-3;
    
    long tries = 100;
    const char *triesEnv = getenv("OFGeometryTestsTries");
    if (triesEnv)
        tries = strtol(triesEnv, NULL, 0);
    
    double overallMaxDiff = 0;
    
    do {
        CGPoint pt1 = _randomPoint(r);
        CGPoint pt2 = _randomPoint(r);
        CGPoint pt3 = _randomPoint(r);
        
        if (_distanceBetweenPoints(pt1, pt2) < minDistance ||
            _distanceBetweenPoints(pt1, pt3) < minDistance ||
            _distanceBetweenPoints(pt2, pt3) < minDistance)
            continue; // too close; try again.
        
        CGPoint v1 = _normalizedVector(_deltaPoint(pt1, pt2));
        CGPoint v2 = _normalizedVector(_deltaPoint(pt1, pt3));
        double dot = _vectorDot(v1, v2);
        if (fabs(dot) > 0.99)
            // too colinear; center will be a long way away and the accuracy will suffer (especially since we pass stuff through CGPoint which is just floats on 32-bit).
            continue;

        CGPoint center = OFCenterOfCircleFromThreePoints(pt1, pt2, pt3);
        
        // All the inputs should be about the same distance from the center
        double d1 = _distanceBetweenPoints(pt1, center);
        double d2 = _distanceBetweenPoints(pt2, center);
        double d3 = _distanceBetweenPoints(pt3, center);
        
        double maxDiff = MAX3(fabs(d1-d2), fabs(d1-d3), fabs(d2-d3));
        
        const double slop = 1e-4;
        
        if (maxDiff >= slop) {
            overallMaxDiff = MAX(overallMaxDiff, maxDiff);
            
            NSLog(@"pt1:%@ pt2:%@ pt3:%@ center:%@ d1:%f d2:%f d3:%f maxDiff:%f (overall %f) dot:%f",
                  NSStringFromPoint(pt1), NSStringFromPoint(pt2), NSStringFromPoint(pt3),
                  NSStringFromPoint(center),
                  d1, d2, d3, maxDiff, overallMaxDiff, dot);
        }
        
        XCTAssertEqualWithAccuracy(d1, d2, slop);
        XCTAssertEqualWithAccuracy(d1, d3, slop);
        XCTAssertEqualWithAccuracy(d2, d3, slop);
        
    } while (tries--);
    
    OFRandomStateDestroy(r);
}

@end
