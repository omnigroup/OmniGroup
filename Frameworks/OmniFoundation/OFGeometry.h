// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <CoreGraphics/CGGeometry.h>
#import <UIKit/UIGeometry.h>
#else
#import <Foundation/NSGeometry.h>

@interface NSValue (NSValueCGGeometryExtensions)
+ (NSValue *)valueWithCGRect:(CGRect)rect;
- (CGRect)CGRectValue;
@end

#endif



@class NSArray, NSMutableArray;

typedef NS_OPTIONS(NSUInteger, OFRectCorner) {
    OFRectCornerMinXMinY = 1 << 0,
    OFRectCornerMaxXMinY = 1 << 1,
    OFRectCornerMaxXMaxY = 1 << 2,
    OFRectCornerMinXMaxY = 1 << 3,
    OFRectCornerAllCorners = ~0UL
};

typedef NS_OPTIONS(NSUInteger, OFRectEdge) {
    OFRectEdgeMinX = 1 << 0,
    OFRectEdgeMaxX = 1 << 1,
    OFRectEdgeMinY = 1 << 2,
    OFRectEdgeMaxY = 1 << 3,
    OFRectEdgeAllEdges = ~0UL
};


/*" Returns the centerpoint of the circle passing through the three specified points. "*/
extern CGPoint OFCenterOfCircleFromThreePoints(CGPoint point1, CGPoint point2, CGPoint point3);

/*" Returns a rect constrained to lie within boundary. This differs from NSIntersectionRect() in that it will adjust the rectangle's origin in order to place it within the boundary rectangle, and will only reduce the rectangle's size if necessary to make it fit. "*/
extern CGRect OFConstrainRect(CGRect rect, CGRect boundary);

/*" Returns a minimum rectangle containing the specified points. "*/
static inline CGRect OFRectFromPoints(CGPoint point1, CGPoint point2)
{
    return CGRectMake(MIN(point1.x, point2.x), MIN(point1.y, point2.y),
                      (CGFloat)fabs(point1.x - point2.x), (CGFloat)fabs(point1.y - point2.y));
}

/*" Returns a rectangle centered on the specified point, large enough to contain the other point. "*/
static inline CGRect OFRectFromCenterAndPoint(CGPoint center, CGPoint corner)
{
    return CGRectMake((CGFloat)(center.x - fabs( corner.x - center.x )),
                      (CGFloat)(center.y - fabs( corner.y - center.y )),
                      (CGFloat)(2 * fabs( corner.x - center.x )),
                      (CGFloat)(2 * fabs( corner.y - center.y )));

}

/*" Returns a rectangle centered on the specified point, and with the specified size. "*/
static inline CGRect OFRectFromCenterAndSize(CGPoint center, CGSize size) {
    return CGRectMake(center.x - (size.width/2), center.y - (size.height/2),
                      size.width, size.height);
}

static inline CGPoint OFRectCenterPoint(CGRect rect)
{
    return CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
}

extern CGFloat OFSquaredDistanceToFitRectInRect(CGRect sourceRect, CGRect destinationRect);
extern CGRect OFClosestRectToRect(CGRect sourceRect, NSArray *candidateRects);
extern void OFUpdateRectsToAvoidRectGivenMinimumSize(NSMutableArray *rects, CGRect rectToAvoid, CGSize minimumSize);
/*" Returns YES if sourceSize is at least as tall and as wide as minimumSize, and that neither the height nor the width of minimumSize is 0. "*/
static inline BOOL OFSizeIsOfMinimumSize(CGSize sourceSize, CGSize minimumSize)
{
    return (sourceSize.width >= minimumSize.width) && (sourceSize.height >= minimumSize.height) && (sourceSize.width > 0.0) && (sourceSize.height > 0.0);
}

extern CGRect OFLargestRectAvoidingRectAndFitSize(CGRect parentRect, CGRect childRect, CGSize fitSize);
#define OFLargestRectAvoidingRect(parentRect, childRect) OFLargestRectAvoidingRectAndFitSize(parentRect, childRect, NSZeroSize)

/*" Returns the rectangle containing both inRect and the point p. "*/
extern CGRect OFRectIncludingPoint(CGRect inRect, CGPoint p);

static inline CGFloat OFSquareOfDistanceFromPointToCenterOfRect(CGPoint pt, CGRect rect)
{
    CGFloat dX = CGRectGetMidX(rect) - pt.x;
    CGFloat dY = CGRectGetMidY(rect) - pt.y;
    return dX*dX + dY*dY;
}

// This is distance. If you really want to know accuracy of each dimension, check them separately.
static inline BOOL OFPointEqualToPointWithAccuracy(CGPoint p1, CGPoint p2, CGFloat accuracy)
{
    CGFloat xDistance = p2.x - p1.x;
    CGFloat yDistance = p2.y - p1.y;
    CGFloat squaredDistance = xDistance*xDistance + yDistance*yDistance;
    return squaredDistance < accuracy;
}

// Checking each dimension. Would area be more meaningful?
static inline BOOL OFSizeEqualToSizeWithAccuracy(CGSize s1, CGSize s2, CGFloat accuracy)
{
    if (fabs(s1.width - s2.width) > accuracy) {
        return false;
    }
    if (fabs(s1.height - s2.height) > accuracy) {
        return false;
    }
    return true;
}

static inline BOOL OFRectEqualToRectWithAccuracy(CGRect r1, CGRect r2, CGFloat accuracy)
{
    return (OFSizeEqualToSizeWithAccuracy(r1.size, r2.size, accuracy) &&
            OFPointEqualToPointWithAccuracy(r1.origin, r2.origin, accuracy));
}

static inline BOOL OFFloatEqualToFloatWithAccuracy(CGFloat f1, CGFloat f2, CGFloat accuracy)
{
    return fabs(f1 - f2) <= accuracy;
}
