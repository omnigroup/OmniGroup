// Copyright 2002-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFGeometry.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

// avoids warning from -Wshadow.  We never use the bessel functions here...
#define y1 _y1

RCS_ID("$Id$");



NSPoint OFCenterOfCircleFromThreePoints(NSPoint point1, NSPoint point2, NSPoint point3)
{
    // from http://www.geocities.com/kiranisingh/center.html
    double x1 = point1.x, y1 = point1.y;
    double x2 = point2.x, y2 = point2.y;
    double x3 = point3.x, y3 = point3.y;
    double N1[2][2] = {
    {x2*x2 + y2*y2 - (x1*x1 + y1*y1), y2 - y1},
    {x3*x3 + y3*y3 - (x1*x1 + y1*y1), y3 - y1}
    };
    double N2[2][2] = {
    {x2 - x1, x2*x2 + y2*y2 - (x1*x1 + y1*y1)},
    {x3 - x1, x3*x3 + y3*y3 - (x1*x1 + y1*y1)}
    };
    double D[2][2] = {
    {x2 - x1, y2 - y1},
    {x3 - x1, y3 - y1}
    };

    double determinantN1 = N1[0][0] * N1[1][1] - N1[1][0] * N1[0][1];
    double determinantN2 = N2[0][0] * N2[1][1] - N2[1][0] * N2[0][1];
    double determinantD = D[0][0] * D[1][1] - D[1][0] * D[0][1];

    return NSMakePoint((float)(determinantN1 / (2.0 * determinantD)), (float)(determinantN2 / (2.0 * determinantD)));
}


NSRect OFRectIncludingPoint(NSRect rect, NSPoint p)
{
    if (p.x < NSMinX(rect)) {
        rect.size.width += NSMinX(rect) - p.x;
        rect.origin.x = p.x;
    } else if (p.x > NSMaxX(rect)) {
        rect.size.width = p.x - NSMinX(rect);
    }
    if (p.y < NSMinY(rect)) {
        rect.size.height += NSMinY(rect) - p.x;
        rect.origin.y = p.y;
    } else if (p.y > NSMaxY(rect)) {
        rect.size.height = p.y - NSMinY(rect);
    }
    return rect;
}

NSRect OFConstrainRect(NSRect rect, NSRect boundary)
{
    rect.size.width = MIN(rect.size.width, boundary.size.width);
    rect.size.height = MIN(rect.size.height, boundary.size.height);
    
    if (NSMinX(rect) < NSMinX(boundary))
        rect.origin.x = boundary.origin.x;
    else if (NSMaxX(rect) > NSMaxX(boundary))
        rect.origin.x = NSMaxX(boundary) - rect.size.width;

    if (NSMinY(rect) < NSMinY(boundary))
        rect.origin.y = boundary.origin.y;
    else if (NSMaxY(rect) > NSMaxY(boundary))
        rect.origin.y = NSMaxY(boundary) - rect.size.height;

    OBPOSTCONDITION(NSContainsRect(boundary, rect));

    return rect;
}

/*" Returns the squared distance from the origin of sourceRect to the closest point in destinationRect. Assumes (and asserts) that destinationRect is large enough to fit sourceRect inside. The reason for returning the squared distance rather than the actual distance is one of optimization - this relieves us of having to take the square root of the product of the squares of the horizontal and vertical distances. The return value is of direct use in comparing against other squared distances, and the square root can be taken if the caller needs the actual distance rather than to simply compare for a variety of potential destination rects. "*/
extern float OFSquaredDistanceToFitRectInRect(NSRect sourceRect, NSRect destinationRect)
{
    float xDistance, yDistance;

    OBASSERT((NSWidth(sourceRect) <= NSWidth(destinationRect)) && (NSHeight(sourceRect) <= NSHeight(destinationRect)));

    if (NSMinX(sourceRect) < NSMinX(destinationRect)) {
        xDistance = NSMinX(destinationRect) - NSMinX(sourceRect);
    } else if (NSMaxX(sourceRect) > NSMaxX(destinationRect)) {
        xDistance = NSMaxX(sourceRect) - NSMaxX(destinationRect);
    } else {
        xDistance = 0.0f;
    }

    if (NSMinY(sourceRect) < NSMinY(destinationRect)) {
        yDistance = NSMinY(destinationRect) - NSMinY(sourceRect);
    } else if (NSMaxY(sourceRect) > NSMaxY(destinationRect)) {
        yDistance = NSMaxY(sourceRect) - NSMaxY(destinationRect);
    } else {
        yDistance = 0.0f;
    }

#if DEBUG_GEOMETRY
    NSLog(@"xDistance: %f, yDistance: %f, sourceRect: %@, destinationRect: %@", xDistance, yDistance, NSStringFromRect(sourceRect), NSStringFromRect(destinationRect));
#endif
    return (xDistance * xDistance) + (yDistance * yDistance);
}

/*" This function returns the candidateRect that is closest to sourceRect. The distance used is the distance required to move sourceRect into the candidateRect, rather than simply having the closest approach. "*/
extern NSRect OFClosestRectToRect(NSRect sourceRect, NSArray *candidateRects)
{
    int rectIndex = [candidateRects count];
    NSRect closestRect = NSZeroRect;
#if DEBUG_GEOMETRY
    NSLog(@"Finding closest rect to %@", NSStringFromRect(sourceRect));
#endif
    if (rectIndex > 0) {
        rectIndex--;
        NSRect rect = [(NSValue *)[candidateRects objectAtIndex:rectIndex] rectValue];
        float shortestDistance = OFSquaredDistanceToFitRectInRect(sourceRect, rect);
        closestRect = rect;

        while (rectIndex-- > 0) {
            NSRect iteratedRect = [(NSValue *)[candidateRects objectAtIndex:rectIndex] rectValue];
            float distance = OFSquaredDistanceToFitRectInRect(sourceRect, iteratedRect);
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
extern void OFUpdateRectsToAvoidRectGivenMinimumSize(NSMutableArray *rects, NSRect rectToAvoid, NSSize minimumSize)
{
    OBPRECONDITION(rects != nil);
    int rectIndex = [rects count];

    // Very important to iterate over the constraining rects _backwards_, as we will be appending to the constraining rects array and also removing some constraining rects as we iterate over them
    while (rectIndex-- > 0) {
        NSRect iteratedRect = [[rects objectAtIndex:rectIndex] rectValue];

#if DEBUG_GEOMETRY
        NSLog(@"%d - %@ (avoiding %@)", rectIndex, NSStringFromRect(iteratedRect), NSStringFromRect(rectToAvoid));
#endif
        if (!NSIntersectsRect(iteratedRect, rectToAvoid)) {
            if (!OFSizeIsOfMinimumSize(iteratedRect.size, minimumSize)) {
                // The constraining rect is too small - remove it
                [rects removeObjectAtIndex:rectIndex];
#if DEBUG_GEOMETRY
                NSLog(@"     too small - removed %@", NSStringFromRect(iteratedRect));
#endif
            }

        } else {
            NSRect workRect;
            
            // Remove the intersecting rect from the list of constraining rects
            [rects removeObjectAtIndex:rectIndex];
#if DEBUG_GEOMETRY
            NSLog(@"     intersects - removed %@", NSStringFromRect(iteratedRect));
#endif
            
            // If there is a non-intersecting portion on the left of the intersecting rect, add that to the list of constraining rects
            workRect = iteratedRect;
            workRect.size.width = NSMinX(rectToAvoid) - NSMinX(iteratedRect);
            if (OFSizeIsOfMinimumSize(workRect.size, minimumSize)) {
                [rects addObject:[NSValue valueWithRect:workRect]];
#if DEBUG_GEOMETRY
                NSLog(@"          added left rect %@", NSStringFromRect(workRect));
#endif
            }

            // Same for the right
            workRect = iteratedRect;
            workRect.origin.x = NSMaxX(rectToAvoid);
            workRect.size.width = NSMaxX(iteratedRect) - NSMaxX(rectToAvoid);
            if (OFSizeIsOfMinimumSize(workRect.size, minimumSize)) {
                [rects addObject:[NSValue valueWithRect:workRect]];
#if DEBUG_GEOMETRY
                NSLog(@"          added right rect %@", NSStringFromRect(workRect));
#endif
            }

            // Same for the top
            workRect = iteratedRect;
            workRect.origin.y = NSMaxY(rectToAvoid);
            workRect.size.height = NSMaxY(iteratedRect) - NSMaxY(rectToAvoid);
            if (OFSizeIsOfMinimumSize(workRect.size, minimumSize)) {
                [rects addObject:[NSValue valueWithRect:workRect]];
#if DEBUG_GEOMETRY
                NSLog(@"          added top rect %@", NSStringFromRect(workRect));
#endif
            }

            // Same for the bottom
            workRect = iteratedRect;
            workRect.size.height = NSMinY(rectToAvoid) - NSMinY(iteratedRect);
            if (OFSizeIsOfMinimumSize(workRect.size, minimumSize)) {
                [rects addObject:[NSValue valueWithRect:workRect]];
#if DEBUG_GEOMETRY
                NSLog(@"          added bottom rect %@", NSStringFromRect(workRect));
#endif
            }
        }
    }
}

/*" This returns the largest of the rects lying to the left, right, top or bottom of the child rect inside the parent rect.  If the two rects do not intersect, parentRect is returned.  If they are the same (or childRect actually contains parentRect), NSZeroRect is returned.  Note that if you which to avoid multiple rects, repeated use of this algorithm is not guaranteed to return the largest non-intersecting rect). "*/
NSRect OFLargestRectAvoidingRectAndFitSize(NSRect parentRect, NSRect childRect, NSSize fitSize)
{
    NSRect rect, bestRect;
    float size, bestSize;

    childRect = NSIntersectionRect(parentRect, childRect);
    if (NSIsEmptyRect(childRect)) {
        // If the child rect doesn't intersect the parent rect, then all of the
        // parent rect avoids the inside rect
        return parentRect;
    }

    // Initialize the result so that if the two rects are equal, we'll
    // return a zero rect.
    bestRect = NSZeroRect;
    bestSize = 0.0f;

    // Test the left rect
    rect.origin = parentRect.origin;
    rect.size.width = NSMinX(childRect) - NSMinX(parentRect);
    rect.size.height = NSHeight(parentRect);

    size = rect.size.height * rect.size.width;
    if (size > bestSize && rect.size.height >= fitSize.height && rect.size.width >= fitSize.width) {
        bestSize = size;
        bestRect = rect;
    }

    // Test the right rect
    rect.origin.x = NSMaxX(childRect);
    rect.origin.y = NSMinY(parentRect);
    rect.size.width = NSMaxX(parentRect) - NSMaxX(childRect);
    rect.size.height = NSHeight(parentRect);

    size = rect.size.height * rect.size.width;
    if (size > bestSize && rect.size.height >= fitSize.height && rect.size.width >= fitSize.width) {
        bestSize = size;
        bestRect = rect;
    }

    // Test the top rect
    rect.origin.x = NSMinX(parentRect);
    rect.origin.y = NSMaxY(childRect);
    rect.size.width = NSWidth(parentRect);
    rect.size.height = NSMaxY(parentRect) - NSMaxY(childRect);

    size = rect.size.height * rect.size.width;
    if (size > bestSize && rect.size.height >= fitSize.height && rect.size.width >= fitSize.width) {
        bestSize = size;
        bestRect = rect;
    }

    // Test the bottom rect
    rect.origin = parentRect.origin;
    rect.size.width = NSWidth(parentRect);
    rect.size.height = NSMinY(childRect) - NSMinY(parentRect);

    size = rect.size.height * rect.size.width;
    if (size > bestSize && rect.size.height >= fitSize.height && rect.size.width >= fitSize.width) {
        //bestSize = size; // clang warns of redundant store
        bestRect = rect;
    }

    return bestRect;
}

