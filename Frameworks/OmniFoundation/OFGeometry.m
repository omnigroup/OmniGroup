// Copyright 2002-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFGeometry.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>
#import <OmniFoundation/OFExtent.h>

// avoids warning from -Wshadow.  We never use the bessel functions here...
#define y1 _y1


#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIGeometry.h>
static inline CGRect _rectFromValue(NSValue *value)
{
    return [value CGRectValue];
}
static inline NSValue *_rectToValue(CGRect rect)
{
    return [NSValue valueWithCGRect:rect];
}
#else
static inline CGRect _rectFromValue(NSValue *value)
{
    return [value rectValue];
}
static inline NSValue *_rectToValue(CGRect rect)
{
    return [NSValue valueWithRect:rect];
}

@implementation NSValue (NSValueCGGeometryExtensions)

+ (NSValue *)valueWithCGRect:(CGRect)rect;
{
    return [self valueWithRect:rect];
}

- (CGRect)CGRectValue;
{
    return [self rectValue];
}

@end

#endif

CGPoint OFCenterOfCircleFromThreePoints(CGPoint point1, CGPoint point2, CGPoint point3)
{
    // from http://www.geocities.com/kiranisingh/center.html
    double x1 = point1.x, y1 = point1.y;
    double x2 = point2.x, y2 = point2.y;
    double x3 = point3.x, y3 = point3.y;
    
    double N1_00 = x2*x2 + y2*y2 - (x1*x1 + y1*y1);
    double N1_01 = y2 - y1;
    double N1_10 = x3*x3 + y3*y3 - (x1*x1 + y1*y1);
    double N1_11 = y3 - y1;

    double N2_00 = x2 - x1;
    double N2_01 = x2*x2 + y2*y2 - (x1*x1 + y1*y1);
    double N2_10 = x3 - x1;
    double N2_11 = x3*x3 + y3*y3 - (x1*x1 + y1*y1);
    
    double D_00 = x2 - x1;
    double D_01 = y2 - y1;
    double D_10 = x3 - x1;
    double D_11 = y3 - y1;

    double determinantN1 = N1_00 * N1_11 - N1_10 * N1_01;
    double determinantN2 = N2_00 * N2_11 - N2_10 * N2_01;
    
    double determinantD = D_00 * D_11 - D_10 * D_01;

    return CGPointMake((float)(determinantN1 / (2.0 * determinantD)), (float)(determinantN2 / (2.0 * determinantD)));
}


CGRect OFRectIncludingPoint(CGRect rect, CGPoint p)
{
    if (p.x < CGRectGetMinX(rect)) {
        rect.size.width += CGRectGetMinX(rect) - p.x;
        rect.origin.x = p.x;
    } else if (p.x > CGRectGetMaxX(rect)) {
        rect.size.width = p.x - CGRectGetMinX(rect);
    }
    if (p.y < CGRectGetMinY(rect)) {
        rect.size.height += CGRectGetMinY(rect) - p.x;
        rect.origin.y = p.y;
    } else if (p.y > CGRectGetMaxY(rect)) {
        rect.size.height = p.y - CGRectGetMinY(rect);
    }
    return rect;
}

CGRect OFConstrainRect(CGRect rect, CGRect boundary)
{
    rect.size.width = MIN(rect.size.width, boundary.size.width);
    rect.size.height = MIN(rect.size.height, boundary.size.height);
    
    if (CGRectGetMinX(rect) < CGRectGetMinX(boundary))
        rect.origin.x = boundary.origin.x;
    else if (CGRectGetMaxX(rect) > CGRectGetMaxX(boundary))
        rect.origin.x = CGRectGetMaxX(boundary) - rect.size.width;

    if (CGRectGetMinY(rect) < CGRectGetMinY(boundary))
        rect.origin.y = boundary.origin.y;
    else if (CGRectGetMaxY(rect) > CGRectGetMaxY(boundary))
        rect.origin.y = CGRectGetMaxY(boundary) - rect.size.height;

    OBPOSTCONDITION(CGRectContainsRect(boundary, rect));

    return rect;
}

/*" Returns the squared distance from the origin of sourceRect to the closest point in destinationRect. Assumes (and asserts) that destinationRect is large enough to fit sourceRect inside. The reason for returning the squared distance rather than the actual distance is one of optimization - this relieves us of having to take the square root of the product of the squares of the horizontal and vertical distances. The return value is of direct use in comparing against other squared distances, and the square root can be taken if the caller needs the actual distance rather than to simply compare for a variety of potential destination rects. "*/
extern CGFloat OFSquaredDistanceToFitRectInRect(CGRect sourceRect, CGRect destinationRect)
{
    CGFloat xDistance, yDistance;

    OBASSERT((CGRectGetWidth(sourceRect) <= CGRectGetWidth(destinationRect)) && (CGRectGetHeight(sourceRect) <= CGRectGetHeight(destinationRect)));

    if (CGRectGetMinX(sourceRect) < CGRectGetMinX(destinationRect)) {
        xDistance = CGRectGetMinX(destinationRect) - CGRectGetMinX(sourceRect);
    } else if (CGRectGetMaxX(sourceRect) > CGRectGetMaxX(destinationRect)) {
        xDistance = CGRectGetMaxX(sourceRect) - CGRectGetMaxX(destinationRect);
    } else {
        xDistance = 0.0f;
    }

    if (CGRectGetMinY(sourceRect) < CGRectGetMinY(destinationRect)) {
        yDistance = CGRectGetMinY(destinationRect) - CGRectGetMinY(sourceRect);
    } else if (CGRectGetMaxY(sourceRect) > CGRectGetMaxY(destinationRect)) {
        yDistance = CGRectGetMaxY(sourceRect) - CGRectGetMaxY(destinationRect);
    } else {
        yDistance = 0.0f;
    }

#if DEBUG_GEOMETRY
    NSLog(@"xDistance: %f, yDistance: %f, sourceRect: %@, destinationRect: %@", xDistance, yDistance, NSStringFromRect(sourceRect), NSStringFromRect(destinationRect));
#endif
    return (xDistance * xDistance) + (yDistance * yDistance);
}

/*" This function returns the candidateRect that is closest to sourceRect. The distance used is the distance required to move sourceRect into the candidateRect, rather than simply having the closest approach. "*/
extern CGRect OFClosestRectToRect(CGRect sourceRect, NSArray *candidateRects)
{
    NSUInteger rectIndex = [candidateRects count];
    CGRect closestRect = CGRectZero;
#if DEBUG_GEOMETRY
    NSLog(@"Finding closest rect to %@", NSStringFromRect(sourceRect));
#endif
    if (rectIndex > 0) {
        rectIndex--;
        CGRect rect = _rectFromValue((NSValue *)[candidateRects objectAtIndex:rectIndex]);
        CGFloat shortestDistance = OFSquaredDistanceToFitRectInRect(sourceRect, rect);
        closestRect = rect;

        while (rectIndex-- > 0) {
            CGRect iteratedRect = _rectFromValue((NSValue *)[candidateRects objectAtIndex:rectIndex]);
            CGFloat distance = OFSquaredDistanceToFitRectInRect(sourceRect, iteratedRect);
#if DEBUG_GEOMETRY
            NSLog(@"%d - distance is %f for %@", rectIndex, distance, NSStringFromRect(iteratedRect));
#endif
            if (distance < shortestDistance) {
#if DEBUG_GEOMETRY
                NSLog(@"     new closestRect: %@", NSStringFromRect(iteratedRect));
#endif
                shortestDistance = distance;
                closestRect = iteratedRect;
            }
        }
    }
    return closestRect;
}

/*" This method splits any of the original rects that intersect rectToAvoid. Note that the rects array must be a mutable array as it is (potentially) modified by this function. Rects which are not as tall or as wide as minimumSize are removed from the original rect array (or never added, if the splitting operation results in any new rects smaller than the minimum size). The end result is that the rects array consists of rects encompassing the same overall area except for any overlap with rectToAvoid, excluding any rects not of minimumSize. No attempt is made to remove duplicate rects or rects which are subsets of other rects in the array. "*/
extern void OFUpdateRectsToAvoidRectGivenMinimumSize(NSMutableArray *rects, CGRect rectToAvoid, CGSize minimumSize)
{
    OBPRECONDITION(rects != nil);
    NSUInteger rectIndex = [rects count];

    // Very important to iterate over the constraining rects _backwards_, as we will be appending to the constraining rects array and also removing some constraining rects as we iterate over them
    while (rectIndex--) {
        CGRect iteratedRect = _rectFromValue([rects objectAtIndex:rectIndex]);

#if DEBUG_GEOMETRY
        NSLog(@"%d - %@ (avoiding %@)", rectIndex, NSStringFromRect(iteratedRect), NSStringFromRect(rectToAvoid));
#endif
        if (!CGRectIntersectsRect(iteratedRect, rectToAvoid)) {
            if (!OFSizeIsOfMinimumSize(iteratedRect.size, minimumSize)) {
                // The constraining rect is too small - remove it
                [rects removeObjectAtIndex:rectIndex];
#if DEBUG_GEOMETRY
                NSLog(@"     too small - removed %@", NSStringFromRect(iteratedRect));
#endif
            }

        } else {
            CGRect workRect;
            
            // Remove the intersecting rect from the list of constraining rects
            [rects removeObjectAtIndex:rectIndex];
#if DEBUG_GEOMETRY
            NSLog(@"     intersects - removed %@", NSStringFromRect(iteratedRect));
#endif
            
            // If there is a non-intersecting portion on the left of the intersecting rect, add that to the list of constraining rects
            workRect = iteratedRect;
            workRect.size.width = CGRectGetMinX(rectToAvoid) - CGRectGetMinX(iteratedRect);
            if (OFSizeIsOfMinimumSize(workRect.size, minimumSize)) {
                [rects addObject:_rectToValue(workRect)];
#if DEBUG_GEOMETRY
                NSLog(@"          added left rect %@", NSStringFromRect(workRect));
#endif
            }

            // Same for the right
            workRect = iteratedRect;
            workRect.origin.x = CGRectGetMaxX(rectToAvoid);
            workRect.size.width = CGRectGetMaxX(iteratedRect) - CGRectGetMaxX(rectToAvoid);
            if (OFSizeIsOfMinimumSize(workRect.size, minimumSize)) {
                [rects addObject:_rectToValue(workRect)];
#if DEBUG_GEOMETRY
                NSLog(@"          added right rect %@", NSStringFromRect(workRect));
#endif
            }

            // Same for the top
            workRect = iteratedRect;
            workRect.origin.y = CGRectGetMaxY(rectToAvoid);
            workRect.size.height = CGRectGetMaxY(iteratedRect) - CGRectGetMaxY(rectToAvoid);
            if (OFSizeIsOfMinimumSize(workRect.size, minimumSize)) {
                [rects addObject:_rectToValue(workRect)];
#if DEBUG_GEOMETRY
                NSLog(@"          added top rect %@", NSStringFromRect(workRect));
#endif
            }

            // Same for the bottom
            workRect = iteratedRect;
            workRect.size.height = CGRectGetMinY(rectToAvoid) - CGRectGetMinY(iteratedRect);
            if (OFSizeIsOfMinimumSize(workRect.size, minimumSize)) {
                [rects addObject:_rectToValue(workRect)];
#if DEBUG_GEOMETRY
                NSLog(@"          added bottom rect %@", NSStringFromRect(workRect));
#endif
            }
        }
    }
}

/*" This returns the largest of the rects lying to the left, right, top or bottom of the child rect inside the parent rect.  If the two rects do not intersect, parentRect is returned.  If they are the same (or childRect actually contains parentRect), CGRectZero is returned.  Note that if you which to avoid multiple rects, repeated use of this algorithm is not guaranteed to return the largest non-intersecting rect). "*/
CGRect OFLargestRectAvoidingRectAndFitSize(CGRect parentRect, CGRect childRect, CGSize fitSize)
{
    childRect = CGRectIntersection(parentRect, childRect);
    if (CGRectIsEmpty(childRect)) {
        // If the child rect doesn't intersect the parent rect, then all of the
        // parent rect avoids the inside rect
        return parentRect;
    }

    // Initialize the result so that if the two rects are equal, we'll
    // return a zero rect.
    CGRect rect, bestRect = CGRectZero;
    CGFloat size, bestSize = (CGFloat)0.0;

    // Test the left rect
    rect.origin = parentRect.origin;
    rect.size.width = CGRectGetMinX(childRect) - CGRectGetMinX(parentRect);
    rect.size.height = CGRectGetHeight(parentRect);

    size = rect.size.height * rect.size.width;
    if (size > bestSize && rect.size.height >= fitSize.height && rect.size.width >= fitSize.width) {
        bestSize = size;
        bestRect = rect;
    }

    // Test the right rect
    rect.origin.x = CGRectGetMaxX(childRect);
    rect.origin.y = CGRectGetMinY(parentRect);
    rect.size.width = CGRectGetMaxX(parentRect) - CGRectGetMaxX(childRect);
    rect.size.height = CGRectGetHeight(parentRect);

    size = rect.size.height * rect.size.width;
    if (size > bestSize && rect.size.height >= fitSize.height && rect.size.width >= fitSize.width) {
        bestSize = size;
        bestRect = rect;
    }

    // Test the top rect
    rect.origin.x = CGRectGetMinX(parentRect);
    rect.origin.y = CGRectGetMaxY(childRect);
    rect.size.width = CGRectGetWidth(parentRect);
    rect.size.height = CGRectGetMaxY(parentRect) - CGRectGetMaxY(childRect);

    size = rect.size.height * rect.size.width;
    if (size > bestSize && rect.size.height >= fitSize.height && rect.size.width >= fitSize.width) {
        bestSize = size;
        bestRect = rect;
    }

    // Test the bottom rect
    rect.origin = parentRect.origin;
    rect.size.width = CGRectGetWidth(parentRect);
    rect.size.height = CGRectGetMinY(childRect) - CGRectGetMinY(parentRect);

    size = rect.size.height * rect.size.width;
    if (size > bestSize && rect.size.height >= fitSize.height && rect.size.width >= fitSize.width) {
        //bestSize = size; // clang warns of redundant store
        bestRect = rect;
    }

    return bestRect;
}

// No size change -- might even overflow
CGRect OFCenteredIntegralRectInRect(CGRect enclosingRect, CGSize toCenter)
{
    CGPoint pt;

    pt.x = CGRectGetMinX(enclosingRect) + (enclosingRect.size.width - toCenter.width)/2;
    pt.y = CGRectGetMinY(enclosingRect) + (enclosingRect.size.height - toCenter.height)/2;

    // TODO: Assuming 1-1 mapping between user and device space
    pt.x = ceil(pt.x);
    pt.y = ceil(pt.y);

    return CGRectMake(pt.x, pt.y, toCenter.width, toCenter.height);
}

CGRect OFLargestCenteredIntegralRectInRectWithAspectRatioAsSize(CGRect enclosingRect, CGSize toCenter)
{
    CGFloat xRatio = enclosingRect.size.width / toCenter.width;
    CGFloat yRatio = enclosingRect.size.height / toCenter.height;

    // Make sure we have an exact match on the min/max edge on the fitting axis
    if (xRatio == yRatio)
        return enclosingRect; // same size already

    CGRect result;
    if (xRatio < yRatio) {
        CGFloat x = enclosingRect.origin.x;
        CGFloat width = enclosingRect.size.width;

        CGFloat height = floor(toCenter.height * xRatio);
        CGFloat y = round(enclosingRect.origin.y + 0.5f * (enclosingRect.size.height - height));

        result = CGRectMake(x, y, width, height);
    } else {
        CGFloat y = enclosingRect.origin.y;
        CGFloat height = enclosingRect.size.height;

        CGFloat width = floor(toCenter.width * yRatio);
        CGFloat x = round(enclosingRect.origin.x + 0.5f * (enclosingRect.size.width - width));

        result = CGRectMake(x, y, width, height);
    }

    // Make sure we really did snap exactly to one pair of sides
    OBASSERT(OFExtentsEqual(OFExtentFromRectXRange(enclosingRect), OFExtentFromRectXRange(result)) ||
             OFExtentsEqual(OFExtentFromRectYRange(enclosingRect), OFExtentFromRectYRange(result)));

    // Make sure we don't overflow on nearly identical rects or whatever
    OBASSERT(CGRectContainsRect(enclosingRect, result));

    // If we use this in a hi dpi context, we'll want to perform this operation in device space, or pass in a context and do the conversion here
    OBASSERT(CGRectEqualToRect(result, CGRectIntegral(result)));

    return result;
}

// Shinks if necessary
CGRect OFCenterAndFitIntegralRectInRectWithSameAspectRatioAsSize(CGRect enclosingRect, CGSize toCenter)
{
    if (toCenter.width <= enclosingRect.size.width && toCenter.height <= enclosingRect.size.height)
        return OFCenteredIntegralRectInRect(enclosingRect, toCenter);
    return OFLargestCenteredIntegralRectInRectWithAspectRatioAsSize(enclosingRect, toCenter);
}

