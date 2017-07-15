// Copyright 2000-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSBezierPath-OAExtensions.h>
#import "NSBezierPath-OAInternal.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/assertions.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$")

#define NONNULL_ARGS __attribute__((nonnull))

#if DEBUGGING_CURVE_INTERSECTIONS
#define CDB(x) x

static const char *straspect(enum OAIntersectionAspect a)
{
    switch(a) {
        case intersectionEntryLeft: return "left";
        case intersectionEntryAt:   return "along";
        case intersectionEntryRight:return "right";
        default:                    return "bogus";
    }
}

#else
#define CDB(x) /* x */
#endif

// This distance should really be passed in from the caller. In Graffle we could adjust it based on the line stroke width.
#define GRAZING_CURVE_BLOOM_DISTANCE 1e-4f

@interface NSBezierPath (PrivateOAExtensions)

/*
 Defined in NSBezierPath-OAInternal.h
 
struct intersectionInfo {
    double leftParameter, rightParameter;
    double leftParameterDistance, rightParameterDistance;
    enum OAIntersectionAspect leftEntryAspect, leftExitAspect;
};
*/

NSString *_roundedStringForPoint(NSPoint point);
static NSRect _parameterizedCurveBounds(const NSPoint *curveCoefficients) NONNULL_ARGS;
// static NSRect _bezierCurveToBounds(const NSPoint *curvePoints);
// wants 4 coefficients and 3 roots
// returns the number of solutions
static unsigned _solveCubic(const double *c, double  *roots, unsigned *multiplicity) NONNULL_ARGS;
void _parameterizeLine(NSPoint *coefficients, NSPoint startPoint, NSPoint endPoint) NONNULL_ARGS;
void _parameterizeCurve(NSPoint *coefficients, NSPoint startPoint, NSPoint endPoint, NSPoint controlPoint1, NSPoint controlPoint2) NONNULL_ARGS;
unsigned intersectionsBetweenLineAndLine(const NSPoint *l1, const NSPoint *l2, struct intersectionInfo *results) NONNULL_ARGS;
unsigned intersectionsBetweenCurveAndLine(const NSPoint *c, const NSPoint *a, struct intersectionInfo *results) NONNULL_ARGS;
unsigned intersectionsBetweenCurveAndCurve(const NSPoint *c1coefficients, const NSPoint *c2coefficients, struct intersectionInfo *results) NONNULL_ARGS;
unsigned intersectionsBetweenCurveAndSelf(const NSPoint *coefficients, struct intersectionInfo *results) NONNULL_ARGS;

struct subpathWalkingState {
    NSBezierPath *pathBeingWalked;      // The NSBezierPath we're iterating through
    NSInteger elementCount;             // [pathBeingWalked elementCount]
    NSPoint startPoint;                 // first point of this subpath, for closepath
    NSBezierPathElement what;           // the type of the current segment/element
    NSPoint points[4];                  // point[0] is currentPoint (derived from previous element)
    NSInteger currentElt;               // index into pathBeingWalked of currently used element
    BOOL possibleImplicitClosepath;     // Fake up a closepath if needed?
    
    // Note that if currentElt >= elementCount, then 'what' may be a faked-up closepath or other element not actually found in the NSBezierPath.
};

BOOL initializeSubpathWalkingState(struct subpathWalkingState *s, NSBezierPath *p, NSInteger startIndex, BOOL implicitClosepath);
BOOL nextSubpathElement(struct subpathWalkingState *s) NONNULL_ARGS;
BOOL hasNextSubpathElement(struct subpathWalkingState *s) NONNULL_ARGS;
void repositionSubpathWalkingState(struct subpathWalkingState *s, NSInteger toIndex) NONNULL_ARGS;

- (BOOL)_curvedIntersection:(CGFloat *)length time:(CGFloat *)time curve:(NSPoint *)c line:(NSPoint *)a;

static BOOL _straightLineIntersectsRect(const NSPoint *a, NSRect rect) NONNULL_ARGS;
// static void _splitCurve(const NSPoint *c, NSPoint *left, NSPoint *right);  // Not currently used
static BOOL _curvedLineIntersectsRect(const NSPoint *c, NSRect rect, CGFloat tolerance) NONNULL_ARGS;

- (BOOL)_curvedLineHit:(NSPoint)point startPoint:(NSPoint)startPoint endPoint:(NSPoint)endPoint controlPoint1:(NSPoint)controlPoint1 controlPoint2:(NSPoint)controlPoint2 position:(CGFloat *)position padding:(CGFloat)padding;
- (BOOL)_straightLineIntersection:(CGFloat *)length time:(CGFloat *)time segment:(NSPoint *)s line:(const NSPoint *)l;
- (BOOL)_straightLineHit:(NSPoint)startPoint :(NSPoint)endPoint :(NSPoint)point  :(CGFloat *)position padding:(CGFloat)padding;
- (NSPoint)_endPointForSegment:(NSInteger)i;

@end

//

struct pointInfo {
    NSPoint pt;
    double tangentX, tangentY;
};

static struct pointInfo getCurvePoint(const NSPoint *c, CGFloat u) NONNULL_ARGS;
static struct pointInfo getLinePoint(const NSPoint *a, CGFloat position) NONNULL_ARGS;

// Returns a point offset to the left (in an increasing-Y-upwards coordinate system, if up==NO) or towards increasing Y (if up==YES)
static inline NSPoint offsetPoint(struct pointInfo pInfo, CGFloat offset, BOOL up)
{
    double length = hypot(pInfo.tangentX, pInfo.tangentY);
    if (length < 1e-15)
        return pInfo.pt;  // sigh
    
    if (up && pInfo.tangentX < 0) {
        pInfo.tangentX = -pInfo.tangentX;
        pInfo.tangentY = -pInfo.tangentY;
    }
    
    return (NSPoint){
        .x = (CGFloat)(pInfo.pt.x - pInfo.tangentY * offset / length),
        .y = (CGFloat)(pInfo.pt.y + pInfo.tangentX * offset / length)
    };
}

static struct pointInfo getCurvePoint(const NSPoint *c, CGFloat u) {
    // Coefficients c[4]
    // Position u
    struct pointInfo i;
    i.pt.x = c[0].x + u * (c[1].x + u * (c[2].x + u * c[3].x));
    i.pt.y = c[0].y + u * (c[1].y + u * (c[2].y + u * c[3].y));
    i.tangentX = c[1].x + u * (2.0f * c[2].x  + u * 3.0f * c[3].x);
    i.tangentY = c[1].y + u * (2.0f * c[2].y  + u * 3.0f * c[3].y);
    return i;
}

static struct pointInfo getLinePoint(const NSPoint *a, CGFloat position) {
    // Coefficients a[2] (not endpoints!)
    return (struct pointInfo){
        .pt = {a[0].x + position * a[1].x, a[0].y + position * a[1].y},
        .tangentX = a[1].x,
        .tangentY = a[1].y
    };
}

@implementation NSBezierPath (OAExtensions)

+ (NSBezierPath *)bezierPathWithRoundedRectangle:(NSRect)rect byRoundingCorners:(OFRectCorner)corners withRadius:(CGFloat)radius;
{
    return [self bezierPathWithRoundedRectangle:rect byRoundingCorners:corners withRadius:radius includingEdges:OFRectEdgeAllEdges];
}

+ (NSBezierPath *)bezierPathWithRoundedRectangle:(NSRect)rect byRoundingCorners:(OFRectCorner)corners withRadius:(CGFloat)radius includingEdges:(OFRectEdge)edges;
{
    NSBezierPath *path = [[NSBezierPath alloc] init];
    [path appendBezierPathWithRoundedRectangle:rect byRoundingCorners:corners withRadius:radius includingEdges:edges];
    return [path autorelease];
}

- (NSPoint)currentpointForSegment:(NSInteger)i
{
    NSPoint points[3];
    NSBezierPathElement element;
    
    if (i == 0) {
        element = [self elementAtIndex:i associatedPoints:points];
        if (element == NSMoveToBezierPathElement)
            return points[0];
        else
            [NSException raise:NSInternalInconsistencyException format:@"Segment %ld has no currentpoint", i];
    }
    
    element = [self elementAtIndex:i-1 associatedPoints:points];
    switch(element) {
        case NSCurveToBezierPathElement:
            return points[2];
        case NSMoveToBezierPathElement:
            return points[0];
        case NSLineToBezierPathElement:
            return points[0];
        default:
            [NSException raise:NSInternalInconsistencyException format:@"Segment %ld has no currentpoint", i];
    }
    
    /* NOTREACHED */
    return (NSPoint){ nanf(""), nanf("") };
}

- (BOOL)strokesSimilarlyIgnoringEndcapsToPath:(NSBezierPath *)otherPath;
{
    return [[self countedSetOfEncodedStrokeSegments] isEqual:[otherPath countedSetOfEncodedStrokeSegments]];
}

- (NSCountedSet *)countedSetOfEncodedStrokeSegments;
{
    NSPoint unlikelyPoint = {(CGFloat)-10275847.33894, (CGFloat)-10275847.33894};
    NSPoint firstPoint = unlikelyPoint, currentPoint = NSZeroPoint;

    NSCountedSet *countedSetOfEncodedStrokeSegments = [NSCountedSet set];
    NSInteger elementIndex, elementCount = [self elementCount];
    for(elementIndex=0; elementIndex<elementCount; elementIndex++) {
        NSPoint points[3];
        NSBezierPathElement element = [self elementAtIndex:elementIndex associatedPoints:points];
        NSString *currentSegmentString = nil;

        switch(element) {
            case NSMoveToBezierPathElement:
                currentPoint = points[0];
                if (NSEqualPoints(firstPoint, unlikelyPoint))
                    firstPoint = currentPoint;
                break;
            case NSClosePathBezierPathElement:
            case NSLineToBezierPathElement: {
                NSString *firstPointString, *lastPointString;

                NSPoint lineToPoint;
                if (element == NSClosePathBezierPathElement)
                    lineToPoint = firstPoint;
                else
                    lineToPoint = points[0];

                if (NSEqualPoints(currentPoint, lineToPoint))
                    break;
                firstPointString = _roundedStringForPoint(currentPoint);
                lastPointString = _roundedStringForPoint(lineToPoint);
                if ([firstPointString compare:lastPointString] == NSOrderedDescending)
                    SWAP(firstPointString, lastPointString);
                currentSegmentString = [NSString stringWithFormat:@"%@%@", firstPointString, lastPointString];
                currentPoint = lineToPoint;
                break;
            }
            case NSCurveToBezierPathElement: {
                NSString *firstPointString, *lastPointString;
                NSString *controlPoint1String, *controlPoint2String;
                NSComparisonResult comparisonResult;

                firstPointString = _roundedStringForPoint(currentPoint);
                controlPoint1String = _roundedStringForPoint(points[0]);
                controlPoint2String = _roundedStringForPoint(points[1]);
                lastPointString = _roundedStringForPoint(points[2]);
                comparisonResult = [firstPointString compare:lastPointString];
                if (comparisonResult == NSOrderedDescending || (comparisonResult == NSOrderedSame && [controlPoint1String compare:controlPoint2String] == NSOrderedDescending)) {
                    SWAP(firstPointString, lastPointString);
                    SWAP(controlPoint1String, controlPoint2String);
                }
                [countedSetOfEncodedStrokeSegments addObject:[NSString stringWithFormat:@"%@%@%@%@", firstPointString, controlPoint1String, controlPoint2String, lastPointString]];
                currentPoint = points[2];
                break;
            }
        }
        if (currentSegmentString != nil)
            [countedSetOfEncodedStrokeSegments addObject:currentSegmentString];
    }

    return countedSetOfEncodedStrokeSegments;
}


//

- (BOOL)intersectsRect:(NSRect)rect
{
    NSInteger count = [self elementCount];
    NSInteger i;
    NSPoint points[3];
    NSPoint startPoint;
    NSPoint currentPoint;
    NSPoint line[2];
    NSPoint curve[4];
    BOOL needANewStartPoint;

    if (count == 0)
        return NO;

    NSBezierPathElement element = [self elementAtIndex:0 associatedPoints:points];
    if (element != NSMoveToBezierPathElement) {
        return NO;  // must start with a moveTo
    }

    startPoint = currentPoint = points[0];
    needANewStartPoint = NO;
    
    for(i=1;i<count;i++) {
        element = [self elementAtIndex:i associatedPoints:points];
        switch(element) {
            case NSMoveToBezierPathElement:
                currentPoint = points[0];
                if (needANewStartPoint) {
                    startPoint = currentPoint;
                    needANewStartPoint = NO;
                }
                break;
            case NSClosePathBezierPathElement:
                _parameterizeLine(line, currentPoint,startPoint);
                if (_straightLineIntersectsRect(line, rect)) {
                    return YES;
                }
                currentPoint = startPoint;
                needANewStartPoint = YES;
                break;
            case NSLineToBezierPathElement:
                _parameterizeLine(line, currentPoint,points[0]);
                if (_straightLineIntersectsRect(line, rect)){
                    return YES;
                }
                currentPoint = points[0];
                break;
            case NSCurveToBezierPathElement: {
                _parameterizeCurve(curve, currentPoint, points[2], points[0], points[1]);
                if (_curvedLineIntersectsRect(curve, rect, [self lineWidth]+1)) {
                    return YES;
                }
                currentPoint = points[2];
                break;
            }
        }
    }

    return NO;
}

static void copyIntersection(OABezierPathIntersection *buf, const struct intersectionInfo *info, NSInteger leftSegment, NSInteger rightSegment)
{
    OABezierPathIntersectionHalf left;
    OABezierPathIntersectionHalf right;
    
    left.segment = leftSegment;
    left.parameter = info->leftParameter;
    left.parameterDistance = info->leftParameterDistance;
    
    right.segment = rightSegment;
    right.parameter = info->rightParameter;
    right.parameterDistance = info->rightParameterDistance;
    
    OBINVARIANT(info->leftParameterDistance >= 0);
    if (info->rightParameterDistance >= 0) {
        left.firstAspect = info->leftEntryAspect;
        left.secondAspect = info->leftExitAspect;
        right.firstAspect = - ( info->leftEntryAspect );
        right.secondAspect = - ( info->leftExitAspect );
    } else {
        left.firstAspect = info->leftExitAspect;
        left.secondAspect = info->leftEntryAspect;
        right.firstAspect = - ( info->leftEntryAspect );
        right.secondAspect = - ( info->leftExitAspect );
    }
    
    buf.left = left;
    buf.right = right;
}

- (BOOL)firstIntersectionWithLine:(OABezierPathIntersection *)result lineStart:(NSPoint)lineStart lineEnd:(NSPoint)lineEnd;
{
    struct subpathWalkingState iter;
    NSPoint lineCoefficients[2];
    double leastParameterSoFar;
    BOOL haveResult;
    
    _parameterizeLine(lineCoefficients, lineStart, lineEnd);
    
    if (!initializeSubpathWalkingState(&iter, self, 0, YES))  // TODO: should we have the implicit closepath?
        return NO;
    
    haveResult = NO;
    
    leastParameterSoFar = 2.0f;  // Greater than any point on the line
    while(nextSubpathElement(&iter)) {
        struct intersectionInfo intersections[MAX_INTERSECTIONS_WITH_LINE];
        NSPoint elementCoefficients[4];
        unsigned intersectionsFound, intersectionIndex;
        
        switch(iter.what) {
            case NSClosePathBezierPathElement:
            case NSLineToBezierPathElement:
                _parameterizeLine(elementCoefficients, iter.points[0], iter.points[1]);
                intersectionsFound = intersectionsBetweenLineAndLine(elementCoefficients, lineCoefficients, intersections);
                break;
            case NSCurveToBezierPathElement:
                _parameterizeCurve(elementCoefficients, iter.points[0], iter.points[3], iter.points[1], iter.points[2]);
                intersectionsFound = intersectionsBetweenCurveAndLine(elementCoefficients, lineCoefficients, intersections);
                break;
            default:
                OBASSERT_NOT_REACHED("Unexpected Bezier path element");
                intersectionsFound = 0;
                break;
        }
        
        OBASSERT(intersectionsFound <= MAX_INTERSECTIONS_WITH_LINE);
        
        for(intersectionIndex = 0; intersectionIndex < intersectionsFound; intersectionIndex ++) {
            BOOL copy = NO;
            if (intersections[intersectionIndex].rightParameter < leastParameterSoFar) {
                leastParameterSoFar = intersections[intersectionIndex].rightParameter;
                copy = YES;
            }
            if (intersections[intersectionIndex].rightParameter + intersections[intersectionIndex].rightParameterDistance < leastParameterSoFar) {
                leastParameterSoFar = intersections[intersectionIndex].rightParameter + intersections[intersectionIndex].rightParameterDistance;
                copy = YES;
            }
            if (copy) {
                haveResult = YES;
                if (result) {
                    copyIntersection(result, &(intersections[intersectionIndex]), iter.currentElt, 0);
                    NSPoint location;
                    location.x = (CGFloat)(lineCoefficients[0].x + leastParameterSoFar * lineCoefficients[1].x);
                    location.y = (CGFloat)(lineCoefficients[0].y + leastParameterSoFar * lineCoefficients[1].y);
                    result.location = location;
                }
            }
        }
    }
    
    return haveResult;
}

static void parameterizeSubpathElement(struct subpathWalkingState *st, NSPoint elementCoefficients[4])
{
    switch(st->what) {
        case NSClosePathBezierPathElement:
        case NSLineToBezierPathElement:
            _parameterizeLine(elementCoefficients, st->points[0], st->points[1]);
            elementCoefficients[2].x = 0;
            elementCoefficients[2].y = 0;
            elementCoefficients[3].x = 0;
            elementCoefficients[3].y = 0;
            break;
        case NSCurveToBezierPathElement:
            _parameterizeCurve(elementCoefficients, st->points[0], st->points[3], st->points[1], st->points[2]);
            break;
        default:
            OBASSERT_NOT_REACHED("Unexpected Bezier path element");
            break;
    }
}

static inline void reverseSenseOfIntersection(struct intersectionInfo *intersection)
{
    enum OAIntersectionAspect origLeftEntryAspect, origLeftExitAspect;
    origLeftEntryAspect = intersection->leftEntryAspect;
    origLeftExitAspect = intersection->leftExitAspect;
    if (intersection->rightParameterDistance >= 0) {
        intersection->leftEntryAspect = -origLeftEntryAspect;
        intersection->leftExitAspect = -origLeftExitAspect;
    } else {
        intersection->leftExitAspect = -origLeftEntryAspect;
        intersection->leftEntryAspect = -origLeftExitAspect;
    }
    SWAP(intersection->leftParameter, intersection->rightParameter);
    SWAP(intersection->leftParameterDistance, intersection->rightParameterDistance);
}

#if 0
static BOOL subsequent(struct OABezierPathIntersectionHalf *one, struct OABezierPathIntersectionHalf *another) {
    if (one->segment == another->segment) {
        return (one->parameter + one->parameterDistance - another->parameter) < EPSILON;
    } else if (one->segment+1 == another->segment) {
        return (one->parameter + one->parameterDistance - 1 - another->parameter) < EPSILON;
    } else if (one->segment-1 == another->segment) {
        return (one->parameter + one->parameterDistance + 1 - another->parameter) < EPSILON;
    } else
        return NO;
}
#endif

- (NSArray *)allIntersectionsWithPath:(NSBezierPath *)other
{
    struct subpathWalkingState selfIter;
    
    if (!initializeSubpathWalkingState(&selfIter, self, 0, NO))
        return [NSArray array];
    
    NSMutableArray *intersections =[[NSMutableArray alloc] init];
    
    while(nextSubpathElement(&selfIter)) {
        struct subpathWalkingState otherIter;
        NSPoint elementCoefficients[4];
        
        if (!initializeSubpathWalkingState(&otherIter, other, 0, NO))
            break;
        
        parameterizeSubpathElement(&selfIter, elementCoefficients);

        while(nextSubpathElement(&otherIter)) {
            NSPoint otherElementCoefficients[4];
            unsigned intersectionsFound, intersectionIndex;
            struct intersectionInfo segmentIntersections[MAX_INTERSECTIONS_PER_ELT_PAIR];

            // Special case for finding self-intersections of a path
            if (self == other && selfIter.currentElt > otherIter.currentElt) {
                // Avoid finding each intersection twice
                continue;
            } else if (self == other && selfIter.currentElt == otherIter.currentElt) {
                // Only curvetos can self-intersect
                if (selfIter.what == NSCurveToBezierPathElement) {
                    intersectionsFound = intersectionsBetweenCurveAndSelf(elementCoefficients, segmentIntersections);
                } else {
                    intersectionsFound = 0;
                }
            } else switch(selfIter.what) {  // This is the usual case
                case NSClosePathBezierPathElement:
                case NSLineToBezierPathElement:
                    switch(otherIter.what) {
                        case NSClosePathBezierPathElement:
                        case NSLineToBezierPathElement:
                            _parameterizeLine(otherElementCoefficients, otherIter.points[0], otherIter.points[1]);
                            intersectionsFound = intersectionsBetweenLineAndLine(elementCoefficients, otherElementCoefficients, segmentIntersections);
                            break;
                        case NSCurveToBezierPathElement:
                            _parameterizeCurve(otherElementCoefficients, otherIter.points[0], otherIter.points[3], otherIter.points[1], otherIter.points[2]);
                            intersectionsFound = intersectionsBetweenCurveAndLine(otherElementCoefficients, elementCoefficients, segmentIntersections);
                            for(intersectionIndex = 0; intersectionIndex < intersectionsFound; intersectionIndex++)
                                reverseSenseOfIntersection(&(segmentIntersections[intersectionIndex]));
                            break;
                        default:
                            OBASSERT_NOT_REACHED("Unexpected Bezier path element");
                            intersectionsFound = 0;
                            break;
                    }
                    break;
                case NSCurveToBezierPathElement:
                    switch(otherIter.what) {
                        case NSClosePathBezierPathElement:
                        case NSLineToBezierPathElement:
                            _parameterizeLine(otherElementCoefficients, otherIter.points[0], otherIter.points[1]);
                            intersectionsFound = intersectionsBetweenCurveAndLine(elementCoefficients, otherElementCoefficients, segmentIntersections);
                            break;
                        case NSCurveToBezierPathElement:
                            _parameterizeCurve(otherElementCoefficients, otherIter.points[0], otherIter.points[3], otherIter.points[1], otherIter.points[2]);
                            intersectionsFound = intersectionsBetweenCurveAndCurve(elementCoefficients, otherElementCoefficients, segmentIntersections);
                            break;
                        default:
                            OBASSERT_NOT_REACHED("Unexpected Bezier path element");
                            intersectionsFound = 0;
                            break;
                    }
                    break;
                default:
                    OBASSERT_NOT_REACHED("Unexpected Bezier path element");
                    intersectionsFound = 0;
                    break;
            }
                
            if (self == other) {
                // Remove unwanted intersection between end of each segment and beginning of the next
#define WEPSILON 1e-4
                
                if (selfIter.currentElt+1 == otherIter.currentElt && intersectionsFound > 0) {
                    struct intersectionInfo i = segmentIntersections[intersectionsFound-1];
                    if (i.leftParameterDistance < EPSILON &&
                        i.leftParameter >= (1 - WEPSILON) &&
                        i.rightParameter <= (WEPSILON)) {
                        intersectionsFound --;
                    }
                } else if (selfIter.currentElt == 1 && !hasNextSubpathElement(&otherIter) && intersectionsFound > 0) {
                    struct intersectionInfo i = segmentIntersections[0];
                    if (i.leftParameterDistance < EPSILON &&
                        i.leftParameter <= (WEPSILON) &&
                        i.rightParameter >= (1 - WEPSILON)) {
#warning 64BIT: Inspect use of sizeof
                        memmove(segmentIntersections+1, segmentIntersections, sizeof(*segmentIntersections)*(--intersectionsFound));
                    }
                }
            }
                    
            NSUInteger earliestInsertionPoint = [intersections count];
            
            for(intersectionIndex = 0; intersectionIndex < intersectionsFound; intersectionIndex++) {
                NSUInteger insertionPoint = [intersections count];
                double t;
                
                // Find where to insert this intersection so that the list remains sorted
                while(insertionPoint > 0 &&
                      ((OABezierPathIntersection *)[intersections objectAtIndex:insertionPoint - 1]).left.parameter > segmentIntersections[intersectionIndex].leftParameter &&
                      ((OABezierPathIntersection *)[intersections objectAtIndex:insertionPoint - 1]).left.segment >= selfIter.currentElt)
                    insertionPoint --;
                
                if (insertionPoint < earliestInsertionPoint)
                    earliestInsertionPoint = insertionPoint;
                
                OABezierPathIntersection *newIntersection = [[OABezierPathIntersection alloc] init];
                copyIntersection(newIntersection, &(segmentIntersections[intersectionIndex]), selfIter.currentElt, otherIter.currentElt);
                
                // parameterizeSubpathElement() fills the higher coefficients with 0 if they're not needed, so we can go ahead and treat everything as a cubic here.
                t = segmentIntersections[intersectionIndex].leftParameter;
                NSPoint location;
                location.x = (CGFloat)((( elementCoefficients[3].x * t + elementCoefficients[2].x ) * t + elementCoefficients[1].x ) * t + elementCoefficients[0].x);
                location.y = (CGFloat)((( elementCoefficients[3].y * t + elementCoefficients[2].y ) * t + elementCoefficients[1].y ) * t + elementCoefficients[0].y);
                newIntersection.location = location;

                [intersections insertObject:newIntersection atIndex:insertionPoint];
                [newIntersection release];
            }
        }
    }
    
    NSArray *result = [NSArray arrayWithArray:intersections];
    [intersections release];
    return result;
}

// TODO: Write unit tests for this. In particular, make sure the winding count comes out right even if the test point is lined up with a vertex or cusp.
- (void)getWinding:(NSInteger *)windingCountPtr andHit:(NSUInteger *)hitCountPtr forPoint:(NSPoint)point;
{
    NSInteger windingCount;
    NSUInteger hitCount;
    struct subpathWalkingState cursor;
    
    windingCount = 0;
    hitCount = 0;
    
    // When counting windings, we count as if the point were at a Y-value infinitesimally greater than its actual Y-value. This avoids difficult situations with vertices at the same Y-coordinate as the test point.
    // For hit counts, we use the actual Y-value.
    
    if (initializeSubpathWalkingState(&cursor, self, 0, YES)) {
        while(nextSubpathElement(&cursor)) {
            switch(cursor.what) {
                case NSClosePathBezierPathElement:
                case NSLineToBezierPathElement:
                    if ((cursor.points[0].y <= point.y || cursor.points[1].y <= point.y) &&
                        (cursor.points[0].y > point.y || cursor.points[1].y > point.y) &&
                        (cursor.points[0].x <= point.x || cursor.points[1].x <= point.x)) {
                        double discern = (cursor.points[0].y - point.y) * (cursor.points[1].x - cursor.points[0].x) - (cursor.points[0].x - point.x) * (cursor.points[0].y - cursor.points[1].y);
                        if (discern == 0)
                            hitCount ++;
                        else if (discern < 0 && (cursor.points[0].y < cursor.points[1].y))
                            windingCount ++;
                        else if (discern > 0 && (cursor.points[0].y > cursor.points[1].y))
                            windingCount --;
                    } else if (cursor.points[0].y == point.y && cursor.points[1].y == point.y &&
                               (cursor.points[0].x <= point.x || cursor.points[1].x <= point.x) &&
                               (cursor.points[0].x >= point.x || cursor.points[1].x >= point.x)) {
                        hitCount ++;
                    }
                    break;
                case NSCurveToBezierPathElement:
                {
                    BOOL above=NO, below=NO;
                    CGFloat leastX, greatestX;
                    leastX = greatestX = cursor.points[0].x;
                    for(unsigned i = 0; i < 4; i++) {
                        if(cursor.points[i].x < leastX)
                            leastX = cursor.points[i].x;
                        else if(cursor.points[i].x >= greatestX)
                            greatestX = cursor.points[i].x;
                        if(cursor.points[i].y <= point.y)
                            below = YES;
                        else if(cursor.points[i].y >= point.y)
                            above = YES;
                    }
                    
                    if (above && below && (leastX <= point.x)) {
                        if (greatestX < point.x) {
                            if (cursor.points[0].y <= point.y && cursor.points[3].y > point.y)
                                windingCount ++;
                            else if (cursor.points[0].y > point.y && cursor.points[3].y <= point.y)
                                windingCount --;
                        } else {
                            NSPoint testLine[2], curveCoeff[4];
                            struct intersectionInfo crossings[MAX_INTERSECTIONS_WITH_LINE];
                            unsigned intersectionsFound, intersectionIndex;
                            
                            testLine[0].x = (CGFloat)(leastX - 1.0);
                            testLine[0].y = point.y;
                            testLine[1].x = point.x - testLine[0].x;
                            testLine[1].y = (CGFloat)0.0;
                            
                            _parameterizeCurve(curveCoeff, cursor.points[0], cursor.points[3], cursor.points[1], cursor.points[2]);
                            intersectionsFound = intersectionsBetweenCurveAndLine(curveCoeff, testLine, crossings);
                            for(intersectionIndex = 0; intersectionIndex < intersectionsFound; intersectionIndex ++) {
                                if (crossings[intersectionIndex].rightParameter < 1.0) {
                                    // TODO: This is probably inadequate. Porbably need to examine entry and exit aspects, as well as seeing whether the rightParameterDistance is positive or negative
                                    switch(crossings[intersectionIndex].leftExitAspect) {
                                        case intersectionEntryLeft:
                                            windingCount ++;
                                            break;
                                        case intersectionEntryRight:
                                            windingCount --;
                                            break;
                                        default:
                                            break;
                                    }
                                } else {
                                    hitCount ++;
                                }
                            }
                        }
                    }
                    break;
                }
                default:
                    OBASSERT_NOT_REACHED("Unexpected Bezier path element");
                    break;
            }
        }
    }
    
    if (windingCountPtr)
        *windingCountPtr = windingCount;
    if (hitCountPtr)
        *hitCountPtr = hitCount;
}

- (BOOL)intersectionWithLine:(NSPoint *)result lineStart:(NSPoint)lineStart lineEnd:(NSPoint)lineEnd
{
    NSPoint curveCoefficients[4];
    NSPoint points[3];
    NSPoint segmentCoefficients[2];
    NSPoint lineCoefficients[2];
    NSPoint startPoint;
    NSPoint currentPoint;
    CGFloat minimumLength = 1.0f;
    NSInteger count = [self elementCount];
    BOOL needANewStartPoint;

    if (count == 0)
        return NO;
        
    NSBezierPathElement element = [self elementAtIndex:0 associatedPoints:points];

    if (element != NSMoveToBezierPathElement) 
        return NO;  // must start with a moveTo

    _parameterizeLine(lineCoefficients,lineStart,lineEnd);
    
    startPoint = currentPoint = points[0];
    needANewStartPoint = NO;
    
    for(NSInteger i=1;i<count;i++) {
        CGFloat ignored, currentLength = 1.0f;

        element = [self elementAtIndex:i associatedPoints:points];
        switch(element) {
            case NSMoveToBezierPathElement:
                currentPoint = points[0];
                if (needANewStartPoint) {
                    startPoint = currentPoint;
                    needANewStartPoint = NO;
                }
                break;
            case NSClosePathBezierPathElement:
                _parameterizeLine(segmentCoefficients,currentPoint,startPoint);
                if ([self _straightLineIntersection:&currentLength time:&ignored segment:segmentCoefficients line:lineCoefficients]) {
                    if (currentLength < minimumLength) {
                        minimumLength = currentLength;
                    }
                }
                currentPoint = startPoint;
                needANewStartPoint = YES;
                break;
            case NSLineToBezierPathElement:
                _parameterizeLine(segmentCoefficients, currentPoint, points[0]);
                if ([self _straightLineIntersection:&currentLength time:&ignored segment:segmentCoefficients line:lineCoefficients]) {
                    if (currentLength < minimumLength) {
                        minimumLength = currentLength;
                    }
                }
                currentPoint = points[0];
                break;
            case NSCurveToBezierPathElement:
                _parameterizeCurve(curveCoefficients, currentPoint, points[2], points[0], points[1]);
                if ([self _curvedIntersection:&currentLength time:&ignored curve:curveCoefficients line:lineCoefficients]) {
                    if (currentLength < minimumLength) {
                        minimumLength = currentLength;
                    }
                }
                currentPoint = points[2];
                break;
        }
    }

    if (minimumLength < 1.0) {
        result->x = lineCoefficients[0].x + minimumLength * lineCoefficients[1].x;
        result->y = lineCoefficients[0].y + minimumLength * lineCoefficients[1].y;
        return YES;
    } else {
        return NO;
    }
}

void splitBezierCurveTo(const NSPoint *c, CGFloat t, NSPoint *l, NSPoint *r)
{
    NSPoint mid;
    CGFloat oneMinusT = 1.0f - t;
    
    l[0] = c[0];
    r[3] = c[3];
    l[1].x = c[0].x * oneMinusT + c[1].x * t;
    l[1].y = c[0].y * oneMinusT + c[1].y * t;
    r[2].x = c[2].x * oneMinusT + c[3].x * t;
    r[2].y = c[2].y * oneMinusT + c[3].y * t;
    mid.x = c[1].x * oneMinusT + c[2].x * t;
    mid.y = c[1].y * oneMinusT + c[2].y * t;
    l[2].x = l[1].x * oneMinusT + mid.x * t;
    l[2].y = l[1].y * oneMinusT + mid.y * t;
    r[1].x = mid.x * oneMinusT + r[2].x * t;
    r[1].y = mid.y * oneMinusT + r[2].y * t;
    l[3].x = l[2].x * oneMinusT + r[1].x * t;
    l[3].y = l[2].y * oneMinusT + r[1].y * t;
    r[0] = l[3];
}

- (NSInteger)segmentHitByPoint:(NSPoint)point padding:(CGFloat)padding {
    CGFloat position = 0;
    return [self segmentHitByPoint:point position:&position padding:padding];
}

- (NSInteger)segmentHitByPoint:(NSPoint)point  {
    CGFloat position = 0;
    return [self segmentHitByPoint:point position:&position padding:5.0f];
}

- (NSInteger)segmentHitByPoint:(NSPoint)point position:(CGFloat *)position padding:(CGFloat)padding;
{
    NSInteger count = [self elementCount];
    NSInteger i;
    NSPoint points[3];
    NSPoint startPoint;
    NSPoint currentPoint;
    BOOL needANewStartPoint;
    
    if (count == 0)
        return 0;
    
    NSBezierPathElement element = [self elementAtIndex:0 associatedPoints:points];
    if (element != NSMoveToBezierPathElement) {
        return 0;  // must start with a moveTo
    }
    
    startPoint = currentPoint = points[0];
    needANewStartPoint = NO;
    
    for(i=1;i<count;i++) {
        element = [self elementAtIndex:i associatedPoints:points];
        if (NSEqualPoints(points[0], point)) {
            if (i==0) {
                i = 1;
            }
            return i;
        }
        switch(element) {
            case NSMoveToBezierPathElement:
                currentPoint = points[0];
                if (needANewStartPoint) {
                    startPoint = currentPoint;
                    needANewStartPoint = NO;
                }
                break;
            case NSClosePathBezierPathElement:
                if ([self _straightLineHit:currentPoint :startPoint :point :position padding:padding]){
                    return i;
                }
                currentPoint = startPoint;
                needANewStartPoint = YES;
                break;
            case NSLineToBezierPathElement:
                if ([self _straightLineHit:currentPoint :points[0] :point :position padding:padding]){
                    return i;
                }
                currentPoint = points[0];
                break;
            case NSCurveToBezierPathElement:
                if ([self _curvedLineHit:point startPoint:currentPoint endPoint:points[2] controlPoint1:points[0] controlPoint2:points[1] position:position padding:padding]) {
                    return i;
                }
                currentPoint = points[2];
                break;
        }
    }
    return 0;
}

- (BOOL)isStrokeHitByPoint:(NSPoint)point padding:(CGFloat)padding
{
    NSInteger segment = [self segmentHitByPoint:point padding:padding];
    return (segment != 0);
}

- (BOOL)isStrokeHitByPoint:(NSPoint)point
{
    NSInteger segment = [self segmentHitByPoint:point padding:5.0f];
    return (segment != 0);
}

- (void)appendBezierPathWithRoundedRectangle:(NSRect)rect withRadius:(CGFloat)radius;
{
    return [self appendBezierPathWithRoundedRectangle:rect byRoundingCorners:OFRectCornerAllCorners withRadius:radius includingEdges:OFRectEdgeAllEdges];
}

- (void)appendBezierPathWithLeftRoundedRectangle:(NSRect)rect withRadius:(CGFloat)radius;
{
    OFRectCorner corners = (OFRectCornerMinXMinY | OFRectCornerMinXMaxY);
    return [self appendBezierPathWithRoundedRectangle:rect byRoundingCorners:corners withRadius:radius includingEdges:OFRectEdgeAllEdges];
}

- (void)appendBezierPathWithRightRoundedRectangle:(NSRect)rect withRadius:(CGFloat)radius;
{
    OFRectCorner corners = (OFRectCornerMaxXMinY | OFRectCornerMaxXMaxY);
    return [self appendBezierPathWithRoundedRectangle:rect byRoundingCorners:corners withRadius:radius includingEdges:OFRectEdgeAllEdges];
}

- (void)appendBezierPathWithRoundedRectangle:(NSRect)rect byRoundingCorners:(OFRectCorner)corners withRadius:(CGFloat)radius includingEdges:(OFRectEdge)edges;
{
    // This is the value AppKit uses in -appendBezierPathWithRoundedRect:xRadius:yRadius:
    
    const CGFloat kControlPointMultiplier = 0.55228;
    
    if (NSIsEmptyRect(rect)) {
        return;
    }
    
    NSBezierPath *bezierPath = [[self class] bezierPath];
    NSPoint startPoint;
    NSPoint sourcePoint;
    NSPoint destPoint;
    NSPoint controlPoint1;
    NSPoint controlPoint2;
    
    CGFloat length = MIN(NSWidth(rect), NSHeight(rect));
    radius = MIN(radius, length / 2.0);
    
    // Top Left (in terms of a non-flipped view)
    BOOL includeCorner = (edges & OFRectEdgeMinX) != 0 || (edges & OFRectEdgeMinY) != 0;
    if ((corners & OFRectCornerMinXMinY) != 0) {
        sourcePoint = NSMakePoint(NSMinX(rect), NSMaxY(rect) - radius);
        startPoint = sourcePoint; // capture for "closing" path without necessarily adding a segment for the final edge
        
        destPoint = NSMakePoint(NSMinX(rect) + radius, NSMaxY(rect));
        
        if (includeCorner) {
            controlPoint1 = sourcePoint;
            controlPoint1.y += radius * kControlPointMultiplier;
            
            controlPoint2 = destPoint;
            controlPoint2.x -= radius * kControlPointMultiplier;
            
            [bezierPath moveToPoint:sourcePoint];
            [bezierPath curveToPoint:destPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
        } else {
            [bezierPath moveToPoint:destPoint];
        }
    } else {
        startPoint = NSMakePoint(NSMinX(rect), NSMaxY(rect));  // capture for "closing" path without necessarily adding a segment for the final edge
        [bezierPath moveToPoint:startPoint];
    }
    
    // Top right (in terms of a flipped view)
    BOOL includeEdge = (edges & OFRectEdgeMinY) != 0;
    includeCorner = (edges & OFRectEdgeMinY) != 0 || (edges & OFRectEdgeMaxX) != 0;
    if ((corners & OFRectCornerMaxXMinY) != 0) {
        sourcePoint = NSMakePoint(NSMaxX(rect) - radius, NSMaxY(rect));
        destPoint = NSMakePoint(NSMaxX(rect), NSMaxY(rect) - radius);
        
        if (includeEdge) {
            [bezierPath lineToPoint:sourcePoint];
        } else {
            [bezierPath moveToPoint:sourcePoint];
        }
        
        if (includeCorner) {
            controlPoint1 = sourcePoint;
            controlPoint1.x += radius * kControlPointMultiplier;
            
            controlPoint2 = destPoint;
            controlPoint2.y += radius * kControlPointMultiplier;
            
            [bezierPath curveToPoint:destPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
        } else {
            [bezierPath moveToPoint:destPoint];
        }
    } else {
        destPoint = NSMakePoint(NSMaxX(rect), NSMaxY(rect));
        if (includeEdge) {
            [bezierPath lineToPoint:destPoint];
        } else {
            [bezierPath moveToPoint:destPoint];
        }
    }
    
    // Bottom right (in terms of a flipped view)
    includeEdge = (edges & OFRectEdgeMaxX) != 0;
    includeCorner = (edges & OFRectEdgeMaxX) != 0 || (edges & OFRectEdgeMaxY) != 0;
    if ((corners & OFRectCornerMaxXMaxY) != 0) {
        sourcePoint = NSMakePoint(NSMaxX(rect), NSMinY(rect) + radius);
        destPoint = NSMakePoint(NSMaxX(rect) - radius, NSMinY(rect));
        
        if (includeEdge) {
            [bezierPath lineToPoint:sourcePoint];
        } else {
            [bezierPath moveToPoint:sourcePoint];
        }
        
        if (includeCorner) {
            controlPoint1 = sourcePoint;
            controlPoint1.y -= radius * kControlPointMultiplier;
            
            controlPoint2 = destPoint;
            controlPoint2.x += radius * kControlPointMultiplier;
            
            [bezierPath curveToPoint:destPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
        } else {
            [bezierPath moveToPoint:destPoint];
        }
    } else {
        destPoint = NSMakePoint(NSMaxX(rect), NSMinY(rect));
        if (includeEdge) {
            [bezierPath lineToPoint:destPoint];
        } else {
            [bezierPath moveToPoint:destPoint];
        }
    }
    
    // Bottom left (in terms of a flipped view)
    includeEdge = (edges & OFRectEdgeMaxY) != 0;
    includeCorner = (edges & OFRectEdgeMaxY) != 0 || (edges & OFRectEdgeMinX) != 0;
    if ((corners & OFRectCornerMinXMaxY) != 0) {
        sourcePoint = NSMakePoint(NSMinX(rect) + radius, NSMinY(rect));
        destPoint = NSMakePoint(NSMinX(rect), NSMinY(rect) + radius);
        
        if (includeEdge) {
            [bezierPath lineToPoint:sourcePoint];
        } else {
            [bezierPath moveToPoint:sourcePoint];
        }
        
        if (includeCorner) {
            controlPoint1 = sourcePoint;
            controlPoint1.x -= radius * kControlPointMultiplier;
            
            controlPoint2 = destPoint;
            controlPoint2.y -= radius * kControlPointMultiplier;
            
            [bezierPath curveToPoint:destPoint controlPoint1:controlPoint1 controlPoint2:controlPoint2];
        } else {
            [bezierPath moveToPoint:destPoint];
        }
    } else {
        destPoint = NSMakePoint(NSMinX(rect), NSMinY(rect));
        if (includeEdge) {
            [bezierPath lineToPoint:destPoint];
        } else {
            [bezierPath moveToPoint:destPoint];
        }
    }
    
    // Back to top Left (in terms of a non-flipped view)
    // CONSIDER: If the top-left corner is rounded, the subpath ends at the beginning of the curve rather than at the top-left corner of the bounding rect (assuming non-flipped coordinates). Is that really what we want if using this for composite paths? Should we do an additional move to (MinX, MinY) of the bounding rect?
    includeEdge = (edges & OFRectEdgeMinX) != 0;
    if (includeEdge) {
        [bezierPath lineToPoint:startPoint];
    } else {
        [bezierPath moveToPoint:startPoint];
    }
    
    [self appendBezierPath: bezierPath];
}

//

- (struct pointInfo)_getPointInfoForPosition:(CGFloat)position {
    NSPoint coefficients[4];
    NSPoint points[3];
    NSInteger segment;
    CGFloat segmentPosition;
    NSInteger segmentCount = [self elementCount] - 1;
    NSPoint startPoint;
    NSBezierPathElement element;

    if (position < 0)
        position = 0;
    if (position > 1)
        position = 1;
    if (position == 1) {
        segment = segmentCount-1;
        segmentPosition = 1;
    } else {
        segment = (NSInteger)floor(position*segmentCount);
        segmentPosition = position * segmentCount - segment;
    }

    startPoint = [self _endPointForSegment:segment];
    if (segmentCount == 0) {
        return (struct pointInfo){ startPoint, 0, 0 }; // ack
    }
    
    element = [self elementAtIndex:segment+1 associatedPoints:points];
    switch(element) {
        case NSClosePathBezierPathElement:
        {
            NSInteger past = segment;
            [self elementAtIndex:0 associatedPoints:points];
            NSPoint bezierEndPoint = points[0];
            while(past--) {
                // Back up until we find the last closepath
                // then step forward to hopefully find a moveto
                element = [self elementAtIndex:past associatedPoints:points];
                if (element == NSClosePathBezierPathElement) {
                    element = [self elementAtIndex:past+1 associatedPoints:points];
                    if (element == NSMoveToBezierPathElement)
                        bezierEndPoint = points[0];
                    break;
                }
            }
            _parameterizeLine(coefficients,startPoint,bezierEndPoint);
            return getLinePoint(coefficients, segmentPosition);
        }
        case NSMoveToBezierPathElement:// PENDING: should probably skip this one
        case NSLineToBezierPathElement: {
            _parameterizeLine(coefficients,startPoint,points[0]);
            return getLinePoint(coefficients, segmentPosition);
        }
        case NSCurveToBezierPathElement: {
            _parameterizeCurve(coefficients, startPoint, points[2], points[0], points[1]);
            return getCurvePoint(coefficients, segmentPosition);
        }
    }
    return (struct pointInfo){ startPoint, 0, 0 }; // ack
}

- (NSPoint)getPointForPosition:(CGFloat)position andOffset:(CGFloat)offset {
    return offsetPoint([self _getPointInfoForPosition:position], -offset, YES);
}

- (NSPoint)getPointForPosition:(OABezierPathPosition)pos
{
    NSPoint points[3];
    NSBezierPathElement element;
    
    if (pos.parameter < EPSILON)
        return [self currentpointForSegment:pos.segment];

    element = [self elementAtIndex:pos.segment associatedPoints:points];
    if (pos.parameter > (1-EPSILON)) {
        switch(element) {
            case NSCurveToBezierPathElement: return points[2];
            case NSLineToBezierPathElement: return points[0];
            case NSMoveToBezierPathElement: return points[0];
            default: /* Else, fall through */ ;
        }
    }
    
    NSPoint startPoint = [self currentpointForSegment:pos.segment];
    NSPoint coefficients[4];

    switch(element) {
        case NSClosePathBezierPathElement:
        {
            NSInteger past = pos.segment;
            while(past--) {
                element = [self elementAtIndex:past associatedPoints:points];
                if (element == NSMoveToBezierPathElement)
                    break;
            }
            if (element != NSMoveToBezierPathElement)
                [NSException raise:NSInternalInconsistencyException format:@"Segment %ld has no preceding moveto", pos.segment];
            /* FALL THROUGH to lineto cxase */
        }
        case NSMoveToBezierPathElement:// PENDING: should probably skip this one
        case NSLineToBezierPathElement: {
            _parameterizeLine(coefficients,startPoint,points[0]);
            return getLinePoint(coefficients, (CGFloat)pos.parameter).pt;
        }
        case NSCurveToBezierPathElement: {
            _parameterizeCurve(coefficients, startPoint, points[2], points[0], points[1]);
            return getCurvePoint(coefficients, (CGFloat)pos.parameter).pt;
        }
    }
    
    [NSException raise:NSInternalInconsistencyException format:@"Segment %ld has unexpected element type %ld", pos.segment, element];
    return (NSPoint){ nanf(""), nanf("") };
}

- (CGFloat)getPositionForPoint:(NSPoint)point {
    CGFloat position =0;
    NSInteger segment = [self segmentHitByPoint:point position:&position padding:5.0f];
    if (segment) {
        position = position + (segment - 1);
        position /= ([self elementCount] - 1);
        return (position);
    }
    return 0.5f; // EEK!
}

// NOTE: Graffle used to rely on this method always returning the "upwards" normal for the line; it no longer does (Graffle performs the upwards constraint itself).
// So this method has been changed to return the "left" normal, since that provides more information to the caller.
- (CGFloat)getNormalForPosition:(CGFloat)position {
    struct pointInfo pInfo = [self _getPointInfoForPosition:position];
    return (CGFloat)(atan2(pInfo.tangentX, - pInfo.tangentY) * 180.0/M_PI);
}

// These use a different interpretation of position than above

static inline double linelength(NSPoint a, NSPoint b)
{
    return hypot(a.x - b.x, a.y - b.y);
}

//
// Compares the length of the control points to the length of the chord and
// subdivides if greater than "error"
//

static double arclength(const NSPoint *V, double error) {
    double chordLength = linelength(V[0], V[3]);
    double boundLength = linelength(V[0], V[1]) + linelength(V[1], V[2]) + linelength(V[2], V[3]);
    
    if((boundLength-chordLength) > error) {
        NSPoint left[4], right[4];
        splitBezierCurveTo(V,0.5f,left,right);                            /* split in two */
        return arclength(left,error/2) + arclength(right,error/2);       /* sum the lengths of each side */
    } else {
        return chordLength;
    }
}

struct lengthAndParameter {
    double length;
    double parameter;
};

// Given a curve, find a point a certain distance along it (or the endpoint, if the curve's too short) and return that point's t-parameter and the distance along the curve.
static struct lengthAndParameter arcLength_l(const NSPoint *V, double maxLength, double lengthErrorBudget)
{
    double chordLength = linelength(V[0], V[3]);
    double boundLength = linelength(V[0], V[1]) + linelength(V[1], V[2]) + linelength(V[2], V[3]);
    // supposedly, boundLength is an upper bound to the length of the arc --- I'm not actually convinced of this yet, but it seems widely believed.
    // chordLength is a lower bound (the straight-line distance between the start and end points).
    OBASSERT(boundLength >= chordLength);
    
    if (boundLength <= maxLength) { // boundLength is less than the length limit, so there's no way we'll be limited by maxLength
        return (struct lengthAndParameter){
            .parameter = 1.0f,
            .length = arclength(V, lengthErrorBudget)
        };
    }
    
    if (boundLength - chordLength <= lengthErrorBudget) {
        // We've subdivided so that the curve is close enough to a straight line here. Approximate.
        double p =  maxLength / boundLength;
        if (p >= 1.0) {
            return (struct lengthAndParameter){
                .parameter = 1.0f,
                .length = boundLength
            };
        } else {
            return (struct lengthAndParameter){
                .parameter = p,
                .length = maxLength
            };
        }
    }
    
    {
        NSPoint left[4], right[4];
        splitBezierCurveTo(V, 0.5f, left, right);
        
        struct lengthAndParameter leftlp = arcLength_l(left, maxLength, lengthErrorBudget/2);
        if (leftlp.length >= maxLength) {
            return (struct lengthAndParameter){
                .parameter = leftlp.parameter / 2,
                .length = leftlp.length
            };
        } else {
            struct lengthAndParameter rightlp = arcLength_l(right, maxLength, lengthErrorBudget/2);
            
            return (struct lengthAndParameter){
                .parameter = (rightlp.parameter + 1) / 2,
                .length = leftlp.length + rightlp.length
            };
        }
    }
}

static double subpathElementLength(struct subpathWalkingState *iter, double errorBudget)
{
    switch(iter->what) {
        case NSClosePathBezierPathElement:
        case NSLineToBezierPathElement:
            return linelength(iter->points[0], iter->points[1]);
        case NSCurveToBezierPathElement:
            return arclength(iter->points, errorBudget);
        default:
            OBASSERT_NOT_REACHED("Unexpected Bezier path element");
            return 0;
    }
}


- (double)lengthToSegment:(NSInteger)seg parameter:(double)parameter totalLength:(double *)totalLengthOut;
{
    struct subpathWalkingState cursor;
    double partialLength;
    double totalLength;
    const double totalErrorBudget = 0.5f;
    
    if (!initializeSubpathWalkingState(&cursor, self, 0, NO)) {
        if (totalLengthOut)
            *totalLengthOut = 0;
        return 0;
    }
    
    partialLength = 0;
    totalLength = 0;
    
    while(nextSubpathElement(&cursor)) {
        
        if (cursor.currentElt < seg || totalLengthOut != NULL) {
            // compute length
            double segmentLength;
            segmentLength = subpathElementLength(&cursor, totalErrorBudget / cursor.elementCount);
            if (cursor.currentElt < seg)
                partialLength += segmentLength;
            totalLength += segmentLength;
        }
        
        if (cursor.currentElt == seg) {
            if (parameter > 0) {
                switch(cursor.what) {
                    case NSClosePathBezierPathElement:
                    case NSLineToBezierPathElement:
                        partialLength += parameter * linelength(cursor.points[0], cursor.points[1]);
                        break;
                    case NSCurveToBezierPathElement: {
                        NSPoint before[4], after[4];
                        splitBezierCurveTo(cursor.points, (CGFloat)parameter, before, after);
                        partialLength += arclength(before, totalErrorBudget / cursor.elementCount);
                        break;
                    }
                    default:
                        OBASSERT_NOT_REACHED("Unexpected Bezier path element");
                        break;
                }
                
                if (totalLengthOut == NULL)
                    return partialLength;
            }
        }
        
    }
    
    if (totalLengthOut != NULL)
        *totalLengthOut = totalLength;
    return partialLength;
}

- (NSInteger)segmentAndParameter:(double *)outParameter afterLength:(double)position fractional:(BOOL)positionIsFractionOfTotal;
{    
    struct subpathWalkingState cursor;
    const double totalErrorBudget = 0.5f;
    
    if (position <= 0.0) {
        if (outParameter)
            *outParameter = 0.0f;
        return 0;
    }
    if (!initializeSubpathWalkingState(&cursor, self, 0, NO)) {
        if (outParameter)
            *outParameter = 0;
        return 0;
    }
    if (positionIsFractionOfTotal && position >= 1.0) {
        if (outParameter)
            *outParameter = 1.0f;
        return cursor.elementCount - 1;
    }
    
    if (positionIsFractionOfTotal) {
        double *lengths;
        double totalLength;
        NSInteger filledLengths, curLength;
        
        lengths = calloc(cursor.elementCount + 1, sizeof(double));
        filledLengths = 0;
        totalLength = 0;

        while(nextSubpathElement(&cursor)) {
            while (filledLengths < cursor.currentElt)
                lengths[filledLengths++] = 0;
            
            double thisLength = subpathElementLength(&cursor, totalErrorBudget / cursor.elementCount);
            lengths[filledLengths++] = thisLength;
            totalLength += thisLength;
        }
        
        position *= totalLength;
        
        for(curLength = 0; curLength < filledLengths; curLength ++) {
            if (position < lengths[curLength])
                break;
            position -= lengths[curLength];
        }
        
        free(lengths);
        
        if (!outParameter)
            return curLength;
        
        repositionSubpathWalkingState(&cursor, curLength);
    } else {
        
        while(nextSubpathElement(&cursor)) {
            double thisLength = subpathElementLength(&cursor, totalErrorBudget / cursor.elementCount);
            if (thisLength < position)
                position -= thisLength;
            else
                break;
        }
        
        if (!outParameter)
            return cursor.currentElt;
    }
    
    double foundParameter;
    switch(cursor.what) {
        case NSClosePathBezierPathElement:
        case NSLineToBezierPathElement:
            foundParameter = position / linelength(cursor.points[0], cursor.points[1]);
            break;
        case NSCurveToBezierPathElement:
            foundParameter = arcLength_l(cursor.points, position, totalErrorBudget / cursor.elementCount).parameter;
            break;
        default:
            OBASSERT_NOT_REACHED("Unexpected Bezier path element");
            foundParameter = 0.0f;
            break;
    }
    
    *outParameter = ( foundParameter > 1.0f ) ? 1.0f : foundParameter;
    return cursor.currentElt;
}

static int compareFloat(const void *a_, const void *b_)
{
    CGFloat a = *(const CGFloat *)a_;
    CGFloat b = *(const CGFloat *)b_;
    
    if (a > b)
        return 1;
    else if (a < b)
        return -1;
    else
        return 0;
}

- (BOOL)isClockwise
{
    OABezierPathIntersection *edge = [[OABezierPathIntersection alloc] init];
    BOOL hit;
    NSRect bounds = [self bounds];
    NSInteger elementCount = [self elementCount], elementIndex, coordinateCount, coordinateIndex;
    
    /* Determine a closed path's clockwiseness by drawing a line through it from outside the bounding box, and then seeing whether the first place it crosses the path is from right to left, or from left to right. */
    
    /* We can have problems if the "probe" line we use is collinear with a path segment, or a couple of other similar cases. To avoid those, we choose a y-value for our horizontal probe line that goes midway between the largest gap between any points' y-coordinates. */
    
    /* Make a list o all elts' y-coordinates, sort it, and run through the list looking for the widest gap */
    CGFloat *yCoordinates = malloc(sizeof(*yCoordinates) * elementCount);
    coordinateCount = 0;
    for(elementIndex = 0; elementIndex < elementCount; elementIndex ++) {
        NSPoint points[3];
        NSBezierPathElement elt = [self elementAtIndex:elementIndex associatedPoints:points];
        if (elt == NSMoveToBezierPathElement || elt == NSLineToBezierPathElement)
            yCoordinates[coordinateCount ++] = points[0].y;
        else if (elt == NSCurveToBezierPathElement)
            yCoordinates[coordinateCount ++] = points[2].y;
        /* Else, a closepath --- ignore, since its y-coordinate would be a duplicate of some moveto's y-coordinate */
    }
    if (coordinateCount < 2) {
        free(yCoordinates);
        [edge release];
        return YES;  // degenerate path
    }

    qsort(yCoordinates, coordinateCount, sizeof(*yCoordinates), compareFloat);
    
    CGFloat bestGapSize, bestGapMidpoint;
    bestGapSize = -1;
    bestGapMidpoint = 0;
    for(coordinateIndex = 1; coordinateIndex < coordinateCount; coordinateIndex ++) {
        CGFloat gap = yCoordinates[coordinateIndex] - yCoordinates[coordinateIndex-1];
        if (gap > bestGapSize) {
            bestGapSize = gap;
            bestGapMidpoint = ( yCoordinates[coordinateIndex] + yCoordinates[coordinateIndex-1] ) / 2.0f;
        }
    }

    free(yCoordinates);
    
    OBASSERT(bestGapSize >= 0.0);
    if (bestGapSize <= 0) {
        [edge release];
        return YES; // another degenerate path
    }
    
    hit = [self firstIntersectionWithLine:edge
                                lineStart:(NSPoint){ .x = NSMinX(bounds) - 1, .y = bestGapMidpoint }
                                  lineEnd:(NSPoint){ .x = NSMaxX(bounds) + 1, .y = bestGapMidpoint }];
    OBASSERT(hit);
    if (hit) {
        enum OAIntersectionAspect aspect = (edge.right.parameterDistance < 0)? edge.right.secondAspect : edge.right.firstAspect;
        [edge release];
        switch(aspect) {
            case intersectionEntryRight:
                return YES;
                break;
            case intersectionEntryLeft:
                return NO;
                break;
            default:
                break;
        }
    } else {
        [edge release]; // need to release `edge` in the not-hit, unreachable case
    }

    // This shouldn't be possible ... 
    OBASSERT_NOT_REACHED("not right or left? huh?");
    return YES;
}

// load and save

- (NSMutableDictionary *)propertyListRepresentation;
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSMutableArray *segments = [NSMutableArray array];
    NSPoint points[3];
    NSInteger count = [self elementCount];
    NSInteger i;

    for(i=0;i<count;i++) {
        NSMutableDictionary *segment = [NSMutableDictionary dictionary];
        NSBezierPathElement element = [self elementAtIndex:i associatedPoints:points];
        
        switch(element) {
            case NSMoveToBezierPathElement:
                [segment setObject:NSStringFromPoint(points[0]) forKey:@"point"];
                [segment setObject:@"MOVETO" forKey:@"element"];
                break;
            case NSClosePathBezierPathElement:
                [segment setObject:@"CLOSE" forKey:@"element"];
                break;
            case NSLineToBezierPathElement:
                [segment setObject:NSStringFromPoint(points[0]) forKey:@"point"];
                [segment setObject:@"LINETO" forKey:@"element"];
                break;
            case NSCurveToBezierPathElement:
                [segment setObject:NSStringFromPoint(points[2]) forKey:@"point"];
                [segment setObject:NSStringFromPoint(points[0]) forKey:@"control1"];
                [segment setObject:NSStringFromPoint(points[1]) forKey:@"control2"];
                [segment setObject:@"CURVETO" forKey:@"element"];
                break;
        }
        [segments addObject:segment];
    }
    [dict setObject:segments forKey:@"elements"];
    
    return dict;
}

- (void)loadPropertyListRepresentation:(NSDictionary *)dict {
    NSArray *segments = [dict objectForKey:@"elements"];
    NSInteger i, count = [segments count];

    for(i=0;i<count;i++) {
        NSDictionary *segment = [segments objectAtIndex:i];
        NSString *element = [segment objectForKey:@"element"];
        if ([element isEqualToString:@"CURVETO"]) {
            NSString *pointString = [segment objectForKey:@"point"];
            NSString *control1String = [segment objectForKey:@"control1"];
            NSString *control2String = [segment objectForKey:@"control2"];
            if (pointString && control1String && control2String) {
                [self curveToPoint:NSPointFromString(pointString) 
                       controlPoint1:NSPointFromString(control1String)
                       controlPoint2:NSPointFromString(control2String)];
            }
        } else if ([element isEqualToString:@"LINETO"]) {
            NSString *pointString = [segment objectForKey:@"point"];
            if (pointString) {
                [self lineToPoint:NSPointFromString(pointString)];
            }
        } else if ([element isEqualToString:@"MOVETO"]) {
            NSString *pointString = [segment objectForKey:@"point"];
            if (pointString) {
                [self moveToPoint:NSPointFromString(pointString)];
            }
        } else if ([element isEqualToString:@"CLOSE"]) {
            [self closePath];
        }
    }
}


// NSObject overrides

- (BOOL)isEqual:(NSBezierPath *)otherBezierPath;
{
    NSInteger elementIndex, elementCount = [self elementCount];

    if (self == otherBezierPath)
        return YES;
    
    if (![otherBezierPath isMemberOfClass:[self class]])
        return NO;

    if ([otherBezierPath elementCount] != elementCount)
        return NO;
    
    for(elementIndex=0; elementIndex<elementCount; elementIndex++) {
        NSPoint points[3];
        NSBezierPathElement element = [self elementAtIndex:elementIndex associatedPoints:points];
        NSPoint otherPoints[3];
        NSBezierPathElement otherElement = [otherBezierPath elementAtIndex:elementIndex associatedPoints:otherPoints];

        if (element != otherElement)
            return NO;
        
        switch (element) {
            case NSMoveToBezierPathElement:
                if (!NSEqualPoints(points[0], otherPoints[0]))
                     return NO;
                break;
            case NSLineToBezierPathElement:
                if (!NSEqualPoints(points[0], otherPoints[0]))
                    return NO;
                break;
            case NSCurveToBezierPathElement:
                if (!NSEqualPoints(points[0], otherPoints[0]) || !NSEqualPoints(points[1], otherPoints[1]) || !NSEqualPoints(points[2], otherPoints[2]))
                    return NO;
                break;
            case NSClosePathBezierPathElement:
                break;
        }
    }

    return YES;
}

static inline NSUInteger _spinLeft(NSUInteger number, NSUInteger spinLeftBitCount)
{
    const NSUInteger bitsPerUnsignedInt = sizeof(NSUInteger) * 8;
    NSUInteger leftmostBits = number >> (bitsPerUnsignedInt - spinLeftBitCount);
    return (number << spinLeftBitCount) | leftmostBits;
}

static inline NSUInteger _threeBitsForPoint(NSPoint point)
{
    CGFloat bothAxes = ABS(point.x) + ABS(point.y);
    return ((NSUInteger)(bothAxes / pow(10.0, floor(log10(bothAxes))))) & 0x7;
}

- (NSUInteger)hash;
{
    NSUInteger hashValue = 0;
    NSInteger elementIndex, elementCount = [self elementCount];

    for(elementIndex=0; elementIndex<elementCount; elementIndex++) {
        NSPoint points[3];
        NSBezierPathElement element = [self elementAtIndex:elementIndex associatedPoints:points];

        switch (element) {
            case NSMoveToBezierPathElement:
                hashValue = _spinLeft(hashValue, 2);
                hashValue ^= 0;
                hashValue = _spinLeft(hashValue, 3);
                hashValue ^= _threeBitsForPoint(points[0]);
                break;
            case NSLineToBezierPathElement:
                hashValue = _spinLeft(hashValue, 2);
                hashValue ^= 1;
                hashValue = _spinLeft(hashValue, 3);
                hashValue ^= _threeBitsForPoint(points[0]);
                break;
            case NSCurveToBezierPathElement:
                hashValue = _spinLeft(hashValue, 2);
                hashValue ^= 2;
                hashValue = _spinLeft(hashValue, 3);
                hashValue ^= _threeBitsForPoint(points[0]);
                hashValue = _spinLeft(hashValue, 3);
                hashValue ^= _threeBitsForPoint(points[1]);
                hashValue = _spinLeft(hashValue, 3);
                hashValue ^= _threeBitsForPoint(points[2]);
                break;
            case NSClosePathBezierPathElement:
                hashValue = _spinLeft(hashValue, 2);
                hashValue ^= 3;
                break;
        }
    }
    return hashValue;
}


@end



@implementation NSBezierPath (PrivateOAExtensions)

// Some utility functions.
// We make heavy use of ranges specified using a pair of doubles as a start and a length. Here are a few functions which manipulate them.
// Some of them are guaranteed to have a positive (or zero) length; others may have a positive or a negative length (for ranges which also encode a direction). In these function names, 'drange' refers to a range with a positive or negative length; 'pdrange' refers to a range whose length is nonnegative, 'ndrange' refers to a range whose length is nonpositive.
static inline BOOL drangeCoversPDrange(double rstart, double rlength, double r2start, double r2length)
{
    OBASSERT(r2length >= 0);
    
    if (rlength > 0)
        return (rstart <= r2start && (rlength - r2length) >= (r2start - rstart) );
    else if (rlength < 0)
        return (rstart >= (r2start + r2length) && (rstart + rlength) <= r2start);
    else
        return (r2length == 0 && rstart == r2start);
}

static inline BOOL pdrangeCoversPDrange(double rstart, double rlength, double r2start, double r2length)
{
    OBASSERT(rlength >= 0);
    OBASSERT(r2length >= 0);
    
    return (rstart <= r2start) && (rlength - r2length >= r2start - rstart);
}

#if 0
static inline BOOL drangeCoversDrange(double rstart, double rlength, double r2start, double r2length)
{
    if (r2length < 0)
        return drangeCoversPDrange(rstart, rlength, r2start + r2length, - r2length);
    else
        return drangeCoversPDrange(rstart, rlength, r2start, r2length);
}
#endif

static BOOL drangeIntersectsDrange(double r1start, double r1length, double r2start, double r2length)
{
    if (r1length < 0) {
        r1start += r1length;
        r1length = -r1length;
    }
    
    return ( (r2start <= (r1start+r1length) || (r2start+r2length <= (r1start+r1length))) &&
             (r2start >= r1start || (r2start+r2length >= r1start)) );
}

static inline void combinePDranges(double *r, double *len, double r1, double r1len, double r2, double r2len)
{
    double newP, newDL, newDR;
    
    if (r1 <= r2) {
        newP = r1; newDL = r1len; newDR = r2len + (r2 - newP);
    } else {
        newP = r2; newDL = r2len; newDR = r1len + (r1 - newP);
    }
    
    *r = newP;
    *len = MAX(newDL, newDR);
}

#if 0
static inline void combineNDranges(double *r, double *len, double r1, double r1len, double r2, double r2len)
{
    double newP, newDL, newDR;
    
    if (r1 >= r2) {
        newP = r1; newDL = r1len; newDR = r2len + (r2 - newP);
    } else {
        newP = r2; newDL = r2len; newDR = r1len + (r1 - newP);
    }
    
    *r = newP;
    *len = MIN(newDL, newDR);
}

static inline void combineDranges(double *r, double *len, double r1, double r1len, double r2, double r2len)
{
    if(r1len >= 0)
        combinePDranges(r, len, r1, r1len, r2, r2len);
    else
        combineNDranges(r, len, r1, r1len, r2, r2len);
}
#endif

NSString *_roundedStringForPoint(NSPoint point)
{
#warning 64BIT: Check formatting arguments
    return [NSString stringWithFormat:@"{%.5f,%.5f}", point.x, point.y];
}

// Given two parameterized monotonic curves, check whether they intersect (abutment counts as intersection)
static BOOL parameterizedMonotonicCurveBoundsIntersect(const NSPoint *curve1, const NSPoint *curve2)
{
    double delta1X = curve1[1].x + curve1[2].x + curve1[3].x;
    double delta1Y = curve1[1].y + curve1[2].y + curve1[3].y;
    double delta2X = curve2[1].x + curve2[2].x + curve2[3].x;
    double delta2Y = curve2[1].y + curve2[2].y + curve2[3].y;
    
    return (drangeIntersectsDrange(curve1[0].x, delta1X, curve2[0].x, delta2X) &&
            drangeIntersectsDrange(curve1[0].y, delta1Y, curve2[0].y, delta2Y));
}


// Returns the bounds of a cubic curve for t=0..1. Curve need not be monotonic.
// Input curve is represented as coefficients.
// This just converts back to the control-point representation and computes the bounding box of the control+end points.
static NSRect _parameterizedCurveBounds(const NSPoint *curve) {
    CGFloat minX = curve[0].x;
    CGFloat maxX = curve[0].x;
    CGFloat minY = curve[0].y;
    CGFloat maxY = curve[0].y;
    NSRect rect;
    NSPoint points[3];
    unsigned i;

    points[0].x = (CGFloat)(curve[0].x + 0.3333* curve[1].x);
    points[0].y = (CGFloat)(curve[0].y + 0.3333* curve[1].y);
    points[1].x = (CGFloat)(curve[0].x + 0.3333* curve[2].x + 0.6666* curve[1].x);
    points[1].y = (CGFloat)(curve[0].y + 0.3333* curve[2].y + 0.6666* curve[1].y);
    points[2].x = (CGFloat)(curve[3].x + curve[2].x + curve[1].x + curve[0].x);
    points[2].y = (CGFloat)(curve[3].y + curve[2].y + curve[1].y + curve[0].y);
    
    for(i=0;i<3;i++) {
        NSPoint p = points[i];
        if (p.x > maxX) {
            maxX = p.x;
        } else if (p.x < minX) {
            minX = p.x;
        }
        if (p.y > maxY) {
            maxY = p.y;
        } else if (p.y < minY) {
            minY = p.y;
        }
    }
    rect.origin.x = minX;
    rect.origin.y = minY;
    rect.size.width = maxX - minX;
    if (rect.size.width < 1) {
        rect.size.width = 1;
    }
    rect.size.height = maxY - minY;
    if (rect.size.height < 1) {
        rect.size.height = 1;
    }
    return rect;
}

// Computes a loose upper and lower bound for the cubic within the specified range, and returns whether the cubic exceeds the given range
static inline BOOL looseCubicExceedsBounds(const double *c,
                                           double tMin, double tMax,
                                           double yMin, double yMax)
{
    // What we're doing here: we do a change of variables so that t'=0..1 follows the path of t=tMin..tMax. Then we convert back to the control-point form of the cubic, and check that each of the control points is within bounds.
    double p0 = (( c[3] * tMin + c[2] ) * tMin + c[1] ) * tMin + c[0];
    if (p0 < yMin || p0 > yMax)
        return YES;
    
    double p1 = c[0] + c[3] * tMax * tMin * tMin + ( c[2] * (tMin + 2 * tMax) * tMin + c[1] * (tMax + 2 * tMin) ) / 3.0f;
    if (p1 < yMin || p1 > yMax)
        return YES;
    
    double p2 = c[0] + c[3] * tMax * tMax * tMin + ( c[2] * (tMax + 2 * tMin) * tMax + c[1] * (tMin + 2 * tMax) ) / 3.0f;
    if (p2 < yMin || p2 > yMax)
        return YES;
    
    double p3 = (( c[3] * tMax + c[2] ) * tMax + c[1] ) * tMax + c[0];
    if (p3 < yMin || p3 > yMax)
        return YES;

    CDB(NSLog(@"Loose bounds(%g %g) --> %g %g %g %g", tMin, tMax, p0, p1, p2, p3);)
    
    return NO;
}

#if 0 // Not currently used
static NSRect _bezierCurveToBounds(const NSPoint *c)
{
    NSPoint low, high;
    
    low.x = MIN(MIN(c[0].x, c[1].x), MIN(c[2].x, c[3].x));
    low.y = MIN(MIN(c[0].y, c[1].y), MIN(c[2].y, c[3].y));
    high.x = MAX(MAX(c[0].x, c[1].x), MAX(c[2].x, c[3].x));
    high.y = MAX(MAX(c[0].y, c[1].y), MAX(c[2].y, c[3].y));
    
    return NSMakeRect(low.x, low.y, high.x - low.x, high.y - low.y);
}
#endif

// wants 4 coefficients and 3 roots
// returns the number of distinct solutions
static unsigned _solveCubic(const double *c, double *roots, unsigned *multiplicity)
{
    // From Graphic Gems 1
    unsigned num = 0;
    double sub;
    double A,B,C;
    double sq_A, p, q;
    double cb_p, D;

    if (c[3] == 0) {
        if (c[2] == 0) {
            if (c[1] == 0) {
                num = 0;
            } else {
                num = 1;
                roots[0] = -c[0]/c[1];
                multiplicity[0] = 1;
            }
        } else {
            double temp;
            // x^3 coefficient is zero, so it's a quadratic
            
            A = c[2];
            B = c[1];
            C = c[0];
            
            temp = B*B - 4*A*C;
            if (fabs(temp) < EPSILON) {
                roots[0] = -B / (2*A);
                num = 1;
                multiplicity[0] = 2;
            } else if(temp < 0) {
                num = 0;
            } else {
                temp = (CGFloat)sqrt(temp);
                roots[0] = (-B-temp)/(2*A);
                multiplicity[0] = 1;
                roots[1] = (-B+temp)/(2*A);
                multiplicity[1] = 1;
                num = 2;
            }
        }
        return num;
    }
    
    // Normal form: x^3 + Ax^2 + Bx + C
    A = c[2] / c[3];
    B = c[1] / c[3];
    C = c[0] / c[3];
    
    // Substitute x = y - A/3 to eliminate the quadric term
    // x^3 + px + q = 0
    // We multiply in some constant factors to avoid dividing early; this gives us less roundoff
    sq_A = A * A;
    p = 3 * B - sq_A;  // this is actually 9*p
    q = (2 * A * sq_A - 9 * A * B + 27 * C) / 2; // this is actually 27*q
    cb_p = p * p * p;  // 729 * p^3
    D = q * q + cb_p;  // 729 * (q^2 + p^3)
    // NSLog(@"Stinky cheese: A=%g (%g), B=%g (%g), C=%g (%g);   D=%g q=%g", A, A-floor(A+0.5), B, B-floor(B+0.5), C, C-floor(C+0.5), D, q);
    
    // (D is the polynomial discriminant, times a constant factor)
    
    if (fabs(D)<EPSILON) {
        if (q==0) {  // one triple solution
            roots[0] = 0;
            multiplicity[0] = 3;
            num = 1;
        } else {     // one single and one double solution
            double u = (CGFloat)cbrt(-q)/3.f;
            roots[0] = 2 * u;
            multiplicity[0] = 1;
            roots[1] = -u;
            multiplicity[1] = 2;
            num = 2;
        }
    } else if (D < 0) { // Casus irreducibilis: three real solutions
        double phi = 1.0f/3 * (CGFloat)acos(-q / (CGFloat)sqrt(-cb_p));  // the extra factors on p^3 and q cancel
        double t = 2 * (CGFloat)sqrt(-p)/3.f;

        roots[0] = t * (CGFloat)cos(phi);
        roots[1] = -t * (CGFloat)cos(phi + M_PI / 3);
        roots[2] = -t * (CGFloat)cos(phi - M_PI / 3);
        multiplicity[0] = 1;
        multiplicity[1] = 1;
        multiplicity[2] = 1;
        num = 3;
    } else {  // One real solution (and a complex conjugate which we ignore)
        double sqrt_D = (CGFloat)sqrt(D);  // 27*sqrt(q^2 + p^3)
        double u = (CGFloat)cbrt(sqrt_D - q);
        double v = -(CGFloat)cbrt(sqrt_D + q);
        roots[0] = (u + v)/3.f;
        multiplicity[0] = 1;
        num = 1;
    }

    // resubstitute

    sub = 1.0f/3 * A;
    for(unsigned i=0;i<num;i++) {
        roots[i] -= sub;
    }

    return num;
}

static unsigned findCubicExtrema(const double *c, double *t)
{
    // Apply the quadratic formula to the derivative.
    // So A = 3c[3], B = 2c[2], C = c[1]
    
    double surd4 = c[2] * c[2] - 3 * c[3] * c[1]; // 1/4 of b^2 - 4ac = 1/4 of 4*c[2] - 4*3*c[3]*c[1]
    if (surd4 < 0)
        return 0; // Derivative has no real-valued zeroes; the cubic is monotonic.
    if (surd4 == 0) {
        t[0] = ( c[2] / ( -3 * c[3] ) );  // -b / 2a
        return 1;
    }
    
    double q = -1 * ( c[2] + (CGFloat)copysign((CGFloat)sqrt(surd4), c[2]) );  // q = -1/2 * [ b +- sqrt(b^2 - 4ac) ]
    
    t[0] = q / ( 3 * c[3] );
    t[1] = c[1] / q;
    
    return 2;
}

static inline double evaluateCubic(const double *c, double x)
{
    // Horner's rule for the win.
    return  (( c[3] * x + c[2] ) * x + c[1] ) * x + c[0];
}

static inline double evaluateCubicDerivative(const double *c, double x)
{
    // returns d/dx of evaluateCubic()
    return  ( 3 * c[3] * x + 2 * c[2] ) * x + c[1];
}

static inline double evaluateCubicSecondDerivative(const double *c, double x)
{
    // returns d/dx of evaluateCubicDerivative()
    return  6 * c[3] * x + 2 * c[2] ;
}

#if 0
static inline OAdPoint evaluateCubicPt(const OAdPoint *c, double t)
{
    return (OAdPoint){
        (( c[3].x * t + c[2].x ) * t + c[1].x ) * t + c[0].x,
        (( c[3].y * t + c[2].y ) * t + c[1].y ) * t + c[0].y
    };
}
#endif

static inline OAdPoint evaluateCubicDerivativePt(const NSPoint *c, double t)
{
    return (OAdPoint){
        ( 3 * c[3].x * t + 2 * c[2].x ) * t + c[1].x,
        ( 3 * c[3].y * t + 2 * c[2].y ) * t + c[1].y
    };
}

void _parameterizeLine(NSPoint *coefficients, NSPoint startPoint, NSPoint endPoint) {
    coefficients[0] = startPoint;
    coefficients[1].x = endPoint.x - startPoint.x;
    if (ABS(coefficients[1].x) < FLATNESS)         // this line is horizontal
        coefficients[1].x = 0;
    coefficients[1].y = endPoint.y - startPoint.y;  // this line is vertical
    if (ABS(coefficients[1].y) < FLATNESS)
        coefficients[1].y = 0;
}

// Given a curveto's endpoints and control points, compute the coefficients to trace out the curve as p(t) = c[0] + c[1]*t + c[2]*t^2 + c[3]*t^3
void _parameterizeCurve(NSPoint *coefficients, NSPoint startPoint, NSPoint endPoint, NSPoint controlPoint1, NSPoint controlPoint2) {
    coefficients[0] = startPoint;
    coefficients[1].x = (CGFloat)(3.0 * (controlPoint1.x - startPoint.x));  // 1st tangent
    coefficients[1].y = (CGFloat)(3.0 * (controlPoint1.y - startPoint.y));  // 1st tangent
    coefficients[2].x = (CGFloat)(3.0 * (startPoint.x - 2 * controlPoint1.x + controlPoint2.x));
    coefficients[2].y = (CGFloat)(3.0 * (startPoint.y - 2 * controlPoint1.y + controlPoint2.y));
    coefficients[3].x = (CGFloat)(endPoint.x - startPoint.x + 3.0 * ( controlPoint1.x - controlPoint2.x ));
    coefficients[3].y = (CGFloat)(endPoint.y - startPoint.y + 3.0 * ( controlPoint1.y - controlPoint2.y ));
}

// Given a parameterized curve, compute a new parameterized curve that goes from 'start' to 'start+len' along the old one
static inline void splitParameterizedCurve(const NSPoint *c, NSPoint *o, double start, double len)
{
    double len2 = len * len, len3 = len * len * len;
    double start2 = start * start;
    double start3 = start * start * start;
    
    o[0].x = (CGFloat)(  c[0].x + c[1].x * start +     c[2].x * start2 +     c[3].x * start3);
    o[1].x = (CGFloat)((          c[1].x +         2 * c[2].x * start  + 3 * c[3].x * start2 ) * len);
    o[2].x = (CGFloat)((                               c[2].x +          3 * c[3].x * start  ) * len2);
    o[3].x = (CGFloat)(                                                      c[3].x            * len3);
    
    o[0].y = (CGFloat)(  c[0].y + c[1].y * start +     c[2].y * start2 +     c[3].y * start3);
    o[1].y = (CGFloat)((          c[1].y +         2 * c[2].y * start  + 3 * c[3].y * start2 ) * len);
    o[2].y = (CGFloat)((                               c[2].y +          3 * c[3].y * start  ) * len2);
    o[3].y = (CGFloat)(                                                      c[3].y            * len3);
}

// Applies an affine transform to the cubic's parameter (not to the cubic's values); ie, substitute t = (a*t' + b)
static inline void affineSubstituteParameter(const NSPoint *inCubic, NSPoint *outCubic, double multiplier, double offset)
{
    return splitParameterizedCurve(inCubic, outCubic, offset, multiplier);
}

#if 0 // No longer used
// Given a parameterized curve, and a section of it (from start to start+len), return the parameterized line between the start point to the end point (the parameterized line has the same directional sense as the underlying curve, even if the range points backwards along the curve)
static void parameterizedLineFromCurveSecant(NSPoint *l, const NSPoint *c, double start, double len)
{
    NSPoint seg[4];
    
    if (len > 0)
        splitParameterizedCurve(c, seg, start, len);
    else
        splitParameterizedCurve(c, seg, start+len, -len);
    
    l[0] = seg[0];
    l[1].x = seg[1].x + seg[2].x + seg[3].x;
    l[1].y = seg[1].y + seg[2].y + seg[3].y;
}
#endif

// Given a parameterized curve c and a parameterized line a, return up to 3 intersections.
unsigned intersectionsBetweenCurveAndLine(const NSPoint *c, const NSPoint *a, struct intersectionInfo *results)
{
    double xcubic[4], ycubic[4];
    double roots[3];
    unsigned multiplicity[3];
    
    // Transform the problem so that the line segment goes from (0,0) to (1,0)
    // (this simplifies the math, and gets rid of the troublesome horizontal / vertical cases)
    xcubic[0] = c[0].x - a[0].x; ycubic[0] = c[0].y - a[0].y;
    for(unsigned i = 1; i < 4; i++) {
        xcubic[i] = c[i].x; ycubic[i] = c[i].y;
    }
    double lineLengthSquared = a[1].x*a[1].x + a[1].y*a[1].y;
    if (lineLengthSquared < EPSILON*EPSILON) {
        return 0;
        // TODO: Handle a single point on a curve?
    }
    for(unsigned i = 0; i < 4; i++) {
        double x =   xcubic[i] * a[1].x + ycubic[i] * a[1].y;
        double y = - xcubic[i] * a[1].y + ycubic[i] * a[1].x;
        xcubic[i] = x / lineLengthSquared;
        ycubic[i] = y /* / lineLengthSquared constant factors are unimportant in y */ ;
    }
    
    // Solve for y==0
    unsigned count = _solveCubic(ycubic, roots, multiplicity);
    
    // Sort the results, since callers require intersections to be returned in order of increasing leftParameter
    if (count > 1) {
        if (roots[0] > roots[1]) {
            SWAP(roots[0], roots[1]);
            SWAP(multiplicity[0], multiplicity[1]);
        }
        if (count > 2) {
            if (roots[0] > roots[2]) {
                double r1 = roots[0];
                double r2 = roots[1];
                unsigned m1 = multiplicity[0];
                unsigned m2 = multiplicity[1];
                roots[0] = roots[2];
                roots[1] = r1;
                roots[2] = r2;
                multiplicity[0] = multiplicity[2];
                multiplicity[1] = m1;
                multiplicity[2] = m2;
            } else if (roots[1] > roots[2]) {
                SWAP(roots[1], roots[2]);
                SWAP(multiplicity[1], multiplicity[2]);
            }
        }
    }
    
    unsigned resultCount = 0;
    
    for(unsigned i=0;i<count;i++) {
        double u = roots[i];
        
        if (u < -0.0001 || u > 1.0001) {
            continue;
        }
        if (isnan(u)) {
            continue;
        }
        
        // The root indicates the cubic's parameter where it intersects. To find the line's parameter, we compute the transformed cubic's x-coordinate.
        double t = evaluateCubic(xcubic, u);
        if (t < -0.0001 || t > 1.0001)
            continue;
        
        results[resultCount].leftParameter = u;
        results[resultCount].rightParameter = t;
        results[resultCount].leftParameterDistance = 0;
        results[resultCount].rightParameterDistance = 0;
        switch(multiplicity[i]) {
            case 1:
            {
                // To figure out the crossing direction, we compute the derivative of the y-coordinate.
                // (The initial transformation is only a rotation+scale, not a reflection, so we don't need to correct for it.)
                double dy = evaluateCubicDerivative(ycubic, u);
                enum OAIntersectionAspect aspect = ( dy < 0 ? intersectionEntryRight : ( dy > 0 ? intersectionEntryLeft : intersectionEntryAt ) ); // Note the aspect is from the curve's point of view
                results[resultCount].leftEntryAspect = aspect;
                results[resultCount].leftExitAspect = aspect;
                break;
            }
            case 2:
            {
                // Osculation is a little confusing, as I learned in high school
                // Compute the second derivative to find out which side we're on
                double ddy = evaluateCubicSecondDerivative(ycubic, u);
                if (ddy < 0) {
                    results[resultCount].leftEntryAspect = intersectionEntryLeft;
                    results[resultCount].leftExitAspect = intersectionEntryRight;
                } else {
                    results[resultCount].leftEntryAspect = intersectionEntryRight;
                    results[resultCount].leftExitAspect = intersectionEntryLeft;
                }
                // TODO: Extend the parameterDistance if |ddy| is small. See extendGrazingIntersection().
                break;
            }
            case 3:
            {
                // The first derivative is zero at the triple root; on either side, though, its sign will be the same as the third derivative, which has the same sign as the x^3 term
                enum OAIntersectionAspect aspect = ( ycubic[3] < 0 ? intersectionEntryRight : ( ycubic[3] > 0 ? intersectionEntryLeft : intersectionEntryAt ) );
                results[resultCount].leftEntryAspect = aspect;
                results[resultCount].leftExitAspect = aspect;
                break;
            }
        }
        
        resultCount++;
    }

    return resultCount;
}

#if 0
#warning 64BIT: Check formatting arguments
#define dlog(expr) printf("%s:%d: %s = %g\n", __func__, __LINE__, #expr, (expr));
#else
#define dlog(expr) /* */
#endif

// Given a parameterized curve c, return at most 1 intersection.
unsigned intersectionsBetweenCurveAndSelf(const NSPoint *c, struct intersectionInfo *results)
{
    /*
     We want to find all pairs of parameters such that bezier(t1) == bezier(t2) and t1 != t2. We can recast that as finding t, d such that bezier(t+d) == bezier(t-d) and d>0. Churning through the algebra, we get
     
             [   3 c1 - 3 s + (- 12 c1 + 6 c2 + 6 s) t + (9 c1 - 9 c2 + 3 e - 3 s) t^2   ]
     d = sqrt[   ---------------------------------------------------------------------   ]
             [                          - 3 c1 + 3 c2 - e + s                            ]
     
     or, in terms of the cubic coefficients,
     
     d = sqrt[  -1 * [ 3 t^2 + 2 c[2]/c[3] t + c[1]/c[3] ] ]
     
     which needs to be satisfied simultaneously in X and Y for the same t.
     */
    
    /* The argument of the sqrt() must be positive, of course, which requires that c[2]^2 >= 3*c[1]*c[3], a quick test for possible self-intersection. */
    if (c[2].x*c[2].x < 3*c[1].x*c[3].x ||
        c[2].y*c[2].y < 3*c[1].y*c[3].y)
        return 0;
    
    /* (The equation above only depends on the ratios c[2]/c[3] and c[1]/c[3]) */
    
    /* Requiring t and d to be simultaneously valid in X and Y boils the equation down to
        
        t =  ( c[1].x/c[3].x - c[1].y/c[3].y ) / ( 2 * c[2].y/c[3].y - 2 * c[2].x/c[3].x )
          =  ( c[1].y*c[3].x - c[1].x*c[3].y ) / ( 2 * c[2].x*c[3].y - 2 * c[2].y*c[3].x )
    */
        
    double t_num = ( c[1].y*c[3].x - c[1].x*c[3].y );
    double t_denom = 2 * ( c[2].x*c[3].y - c[2].y*c[3].x );
    double t_other = c[1].x*c[2].y - c[1].y*c[2].x;
    
    dlog(t_num);
    dlog(t_denom);
    
    /* Another early check: make sure that 0<t<1. 't' isn't the value we're actually interested in (we want t +- d), but if t is outside of the range 0..1, then at least one of the intersections will be too, meaning that we won't return anything. The real reason for doing this check is to avoid the case where t_denom == 0. */
    
    // Return early if |t| >= 1
    if (fabs(t_num) >= fabs(t_denom))
        return 0;
    
    // Return early if t < 0
    double t = t_num / t_denom;
    dlog(t);
    if (t < 0)
        return 0;
    
    dlog(c[1].x);
    dlog(c[2].x);
    dlog(c[3].x);
    double dsquared = 2 * t_other / t_denom - 3 * t * t;
    dlog(dsquared);
    
    // A final check: if we can't get a positive d^2 (real-valued d), then there is no self-intersection.
    if (dsquared <= 0)
        return 0;
    
    double d = (CGFloat)sqrt(dsquared);
    dlog(d);
    
    // No self-intersection if either (t+d) or (t-d) are outside the range 0..1
    if (t<d || (t+d)>1)
        return 0;
    
    // For the aspect, we check the sign of the crossproduct of the tangent vectors at (t-d) and (t+d).
    /*
     double crossproduct = (2*t_other - 3*t_num*t - 3*dsquared*t_denom)*2*d;
     
     but since d > 0, the sign is unchanged if we divide it out
    */
    double crossproduct = (2*t_other - 3*t_num*t - 3*dsquared*t_denom);
    dlog(crossproduct);

    results[0].leftParameter = t - d;
    results[0].rightParameter = t + d;
    results[0].leftParameterDistance = 0;
    results[0].rightParameterDistance = 0;
    enum OAIntersectionAspect aspect = ( crossproduct > 0 ) ? intersectionEntryRight : (crossproduct < 0) ? intersectionEntryLeft : intersectionEntryAt;
    // TODO: Can a cubic self-osculate?
    results[0].leftEntryAspect = aspect;
    results[0].leftExitAspect = aspect;
    
    return 1;
}

/*
 Given a line's tangent vector, and the offset to a point on another line that's about to cross this one,
 return the intersection aspect (is it on the right hand or the left hand side of this line)
*/
static inline enum OAIntersectionAspect lineAspect(OAdPoint tangent, double offsetX, double offsetY)
{
    double cross = tangent.x * offsetY - tangent.y * offsetX;
    if (cross > 0) {
#warning 64BIT: Check formatting arguments
        CDB(printf(" right aspect from dx=%g dy=%g\n", offsetX, offsetY);)
        return intersectionEntryRight;
    } else if (cross < 0) {
#warning 64BIT: Check formatting arguments
        CDB(printf(" left  aspect from dx=%g dy=%g\n", offsetX, offsetY);)
        return intersectionEntryLeft;
    } else {
#warning 64BIT: Check formatting arguments
        CDB(printf(" along aspect from dx=%g dy=%g\n", offsetX, offsetY);)
        return intersectionEntryAt;
    }
}

static inline double dotprod(double x, double y, NSPoint xy0, NSPoint xy1)
{
    return (x - xy0.x) * xy1.x + (y - xy0.y) * xy1.y;
}

static inline double vecmag(double a, double b)
{
    return hypot(a, b);
}

// This returns (a/b), clipping the result to 1.
// (Safely returns 1 for the (0/0) case as well.)
// Caller assures that a/b is not negative.
static inline double clip_div(double dotproduct, double vecmag)
{
    if (fabs(dotproduct) >= fabs(vecmag))
        return 1.0f;
    else
        return dotproduct / vecmag;
}

// Given two lines l1, l2: return zero or one intersections. May return intersections with nonzero distance.
unsigned intersectionsBetweenLineAndLine(const NSPoint *l1, const NSPoint *l2, struct intersectionInfo *results)
{
    double pdet, vdet, other_pdet;
        
    // NSLog(@"Line 1: (%g,%g)->(%g,%g)    Line 2: (%g,%g)->(%g,%g)", l1[0].x,l1[0].y, l1[1].x,l1[1].y, l2[0].x,l2[0].y, l2[1].x,l2[1].y); 

    pdet = ( l1[0].x - l2[0].x ) * l2[1].y - ( l1[0].y - l2[0].y ) * l2[1].x;
    vdet = l1[1].x * l2[1].y - l1[1].y * l2[1].x;
    other_pdet = ( l2[0].x - l1[0].x ) * l1[1].y - ( l2[0].y - l1[0].y ) * l1[1].x;  // pdet, with l1 and l2 swapped
    // double other_vdet = - vdet;  // vdet, with l1 and l2 swapped
    
    // NSLog(@"Determinants: %g/%g  and  %g/%g", pdet, vdet, other_pdet, -vdet);
    
    if (pdet != 0 && signbit(pdet) == signbit(vdet)) {
        // l1 diverges from l2, no intersection.
        return 0;
    } else if (other_pdet != 0 && signbit(other_pdet) != signbit(vdet)) {
        // l2 diverges from l1, no intersection.
        return 0;
    } else if (fabs(pdet) > fabs(vdet) || fabs(other_pdet) > fabs(vdet)) {
        // Either parallel (vdet==0), or convergent but not fast enough to cross within the length of l1. (or l2, in the case of other_pdet).
        return 0;
    } else if (fabs(vdet) > EPSILON) {
        // The straightforward crossing-lines case.
        results[0].leftParameter = - pdet / vdet;
        results[0].rightParameter = other_pdet / vdet;
        results[0].leftParameterDistance = 0;
        results[0].rightParameterDistance = 0;
        results[0].leftEntryAspect = vdet > 0 ? intersectionEntryRight : intersectionEntryLeft;
        results[0].leftExitAspect = results[0].leftEntryAspect;
        return 1;
    } else {
        // Parallel and collinear. Annoying case, but pretty common in actual use of Graffle.
        // (This is also where you end up if l2 is zero-length, another not unheard-of situation.)
        // The following algorithm isn't fastest, but it's well-behaved. I'll waste a few of those GHz on correctness.
        double dot0 = dotprod(l1[0].x, l1[0].y, l2[0], l2[1]);                        // Projecting start of l1 onto l2.
        double dot1 = dotprod(l1[0].x + l1[1].x, l1[0].y + l1[1].y, l2[0], l2[1]);    // Projecting end of l1 onto l2.
        if (dot0 < 0 && dot1 < 0) {
            // l1 is completely before l2.
            return 0;
        }
        double l1len2 = l1[1].x*l1[1].x + l1[1].y*l1[1].y;  // squared length of l1
        double l2len2 = l2[1].x*l2[1].x + l2[1].y*l2[1].y;  // squared length of l2
        if (dot0 > l2len2 && dot1 > l2len2) {
            // l1 is completely after l2.
            return 0;
        }
        if (l2len2 <= EPSILON*EPSILON) {
            // l2 is zero-length, but is in line with l1.
            if (l1len2 <= EPSILON*EPSILON) {
                // l1 is zero-length also. j00 suxx0r!
                if (NSEqualPoints(l1[0],l2[0])) {
                    results[0].leftParameter = 0;
                    results[0].leftParameterDistance = 1;
                    results[0].rightParameter = 0;
                    results[0].rightParameterDistance = 1;
                    results[0].leftEntryAspect = intersectionEntryAt;
                    results[0].leftExitAspect = intersectionEntryAt;
                    return 1;  // One result in the buffer.
                } else {
                    return 0;  // No intersection.
                }
            } else {
                // Project l2 onto l1.
                double l1parameter = dotprod(l2[0].x, l2[0].y, l1[0], l1[1]);
                if (l1parameter >= 0 && l1parameter <= l1len2) {
                    results[0].leftParameter = l1parameter / l1len2;
                    results[0].leftParameterDistance = 0;
                    results[0].rightParameter = 0;
                    results[0].rightParameterDistance = 1;
                    results[0].leftEntryAspect = intersectionEntryAt;
                    results[0].leftExitAspect = intersectionEntryAt;
                    return 1;
                } else {
                    // Past the end of the line. No intersection.
                    return 0;
                }
            }
        }
        // Okay, there's overlap. Now, compute the overlap range in terms of each line's parameters... "start" and "end" are in terms of l1, which means that they might be going backwards along l2 if the two segments are antiparallel.
        double leftParameterStart, rightParameterStart, leftParameterEnd, rightParameterEnd;
        // NSLog(@"dot0 = %g, dot1 = %g, l1len2 = %g, l2len2 = %g", dot0, dot1, l1len2, l2len2);
        if (dot0 > l2len2) {
            // <5>
            // l1[0] is past the end of l2, but l1 points back into l2. Similar to case <2>, but the lines are antiparallel.
            double dot = dotprod(l2[0].x+l2[1].x, l2[0].y+l2[1].y, l1[0], l1[1]);  // Project end of l2 onto l1.
            leftParameterStart  = clip_div(dot, l1len2);           // overlap starts here along l1
            rightParameterStart = 1;                               // overlap starts as soon as we find l2, starting at its end
        } else if (dot0 >= 0) {
            // <1>
            // l1[0] is somewhere inside the l2 line segment.
            leftParameterStart  = 0;                              // overlap starts at t=0 along l1
            rightParameterStart = clip_div(dot0, l2len2);    // overlap starts here along l2
        } else {
            // <2>
            // l1[0] is outside the l2 line segment, but l1 heads into l2, so find where l2 starts.
            // we compute the dot products in the other order:
            double dot = dotprod(l2[0].x, l2[0].y, l1[0], l1[1]);  // Project beginning of l2 onto l1.
            // note that we know that l1 and l2 are pointing in the same direction, which simplifies the logic in here.
            leftParameterStart  = clip_div(dot, l1len2);   // overlap starts here along l1
            rightParameterStart = 0;                              // overlap starts as soon as we find l2
        }
        if (dot1 >= l2len2) {
            // <6>
            // l1[end] is past the end of the l2 line segment, but they're pointing in the same direction.
            double dot = dotprod(l2[0].x+l2[1].x, l2[0].y+l2[1].y, l1[0], l1[1]);  // Project end of l2 onto l1.
            leftParameterEnd = clip_div(dot, l1len2);
            rightParameterEnd = 1;
        } else if (dot1 >= 0) {
            // <3>
            // l1[end] is somewhere inside the l2 line segment.
            leftParameterEnd = 1;                                 // overlap continues through end of l1
            rightParameterEnd = clip_div(dot1, l2len2);      // overlap ends here along l2
        } else {
            // <4>
            // l1[end] is somewhere before the l2 line segment. Since we would have already caught the case where they're both before l2, the segments must be antiparallel, with l1[start] inside (or after) l2. This is the companion to case <2>.
            double dot = dotprod(l2[0].x, l2[0].y, l1[0], l1[1]);  // Project beginning of l2 onto l1.
            leftParameterEnd = clip_div(dot, l1len2);
            rightParameterEnd = 0;
        }
        // Copy the ranges into the results buffer.
        results[0].leftParameter = leftParameterStart;
        results[0].leftParameterDistance = leftParameterEnd - leftParameterStart;
        results[0].rightParameter = rightParameterStart;
        results[0].rightParameterDistance = rightParameterEnd - rightParameterStart;
        results[0].leftEntryAspect = intersectionEntryAt;
        results[0].leftExitAspect = intersectionEntryAt;
        return 1;  // One result in the buffer.
    }
}

// This is used by intersectionsBetweenCurveAndCurve[Monotonic]() to combine the results of the recursive subdivision
static unsigned mergeSortIntersectionInfo(struct intersectionInfo *buf, unsigned count1, unsigned count2, double leftBoundary, double rightBoundary)
{
    // Even though this is a mergesort, it's still pretty much O(N^2), because the memmove() is O(N). However, N is quite small.
#define MEPSILON 1e-8
    unsigned returned;
    returned = 0;
    while (count1 > 0 && count2 > 0) {
        // Combine duplicate entries: this often happens at the edge of a sliced-up segment
        // TODO: The segment boundary is passed in to us (leftBoundary,rightBoundary); we should only combine near the boundary? (but really, if we need that test, then that means that some other case will put the apparent duplicate near a boundary and we'll mess up: better to not rely on it)
        if (buf[0].leftEntryAspect == buf[count1].leftEntryAspect &&
            buf[0].leftExitAspect == buf[count1].leftExitAspect &&
            fabs(buf[0].leftParameter - buf[count1].leftParameter) < MEPSILON &&
            fabs(buf[0].rightParameter - buf[count1].rightParameter) < MEPSILON &&
            fabs(buf[0].leftParameterDistance - buf[count1].leftParameterDistance) < MEPSILON &&
            fabs(buf[0].rightParameterDistance - buf[count1].rightParameterDistance) < MEPSILON) {
            // NSLog(@"Dup %g %g %g %g", (buf[0].leftParameter - buf[count1].leftParameter), (buf[0].rightParameter - buf[count1].rightParameter), (buf[0].leftParameterDistance - buf[count1].leftParameterDistance), (buf[0].rightParameterDistance - buf[count1].rightParameterDistance));
            // Simply drop the element at buf[count1].
            // TODO: Merge the ranges if the distances are nonzero?
#warning 64BIT: Inspect use of sizeof
            memmove(&(buf[count1]), &(buf[count1+1]), sizeof(*buf)*(count1-1));
            count2 --;
        } else if (buf[0].leftParameter <= buf[count1].leftParameter) {
            // Copy the element at *buf into the output buffer (which means just adjusting a pointer)
            count1 --;
            buf ++;
            returned ++;
        } else {
            // Copy the element at buf[count1] into the output buffer (must move the rest of the left-side entries up one, to make room)
            struct intersectionInfo tmp = buf[count1];
#warning 64BIT: Inspect use of sizeof
            memmove(&(buf[1]), &(buf[0]), sizeof(*buf) * count1);
            buf[0] = tmp;
            count2 --;
            buf ++;
            returned ++;
        }
    }
    
    return returned + count1 + count2;
}

// Given an interval around 0 and a cubic, restrict the interval to not go past any intersections between the cubic and the x-axis
static inline void shrinkIntervalToRoots(const double poly[4], double *min, double *max)
{
    double roots[3];
    unsigned dummy[3];
    unsigned count, root;
    
    count = _solveCubic(poly, roots, dummy);
    for(root = 0; root < count; root ++) {
        double r = roots[root];
        if (r < 0 && r > *min)
            *min = r;
        if (r > 0 && r < *max)
            *max = r;
    }
}

// Given an intersection found between two cubics, figure out whether the cubics are running along essentially the same path (either because they're identical, or they're tangent with similar curvature). If so, extend the distance of the intersection to a nonzero value.
// We can't do this before we find an intersection because we won't know how to match up the two curves' parameters.
static BOOL extendGrazingIntersection(const NSPoint *c1coeff, const NSPoint *c2coeff,
                                      struct intersectionInfo *i,
                                      double bloom)
{
    OAdPoint c1tangent = evaluateCubicDerivativePt(c1coeff, i->leftParameter);
    OAdPoint c2tangent = evaluateCubicDerivativePt(c2coeff, i->rightParameter);
    double c1tangentmag2 = c1tangent.x * c1tangent.x + c1tangent.y * c1tangent.y;
    double c2tangentmag2 = c2tangent.x * c2tangent.x + c2tangent.y * c2tangent.y;
    double c1dotc2 = c1tangent.x * c2tangent.x + c1tangent.y * c2tangent.y;
    
    // If the tangents are nearly parallel (or antiparallel), we might have a grazing intersection to extend.
    // arccos(sqrt(1 - 1/256)) = about 3.6 degrees
    if ((c1dotc2 * c1dotc2) < (1. - 1./256.) * (c1tangentmag2 * c2tangentmag2))
        return NO;
    
    // Find the t-parameter ratio
    // Project both vectors onto an intermediate vector and find the ratio of the magnitudes of the projections along this axis; multiply each curve's t-parameter by the other curve's tangent-vector-magnitude so that the shared curves have the same tangent vector (or as close as possible)
    // If you use the sum of the vectors as the intermediate vector, then the math gets pretty simple (if the vectors are antiparallel, then negate one of them before summing)
    // the copysign+fabs below makes sure that the ratio has the right sign, but rightRate is positive, so that the Tshared parameter moves in the same direction as the left curve's t parameter: makes things easier later
    double leftRate = (CGFloat)copysign(c1tangentmag2, c1dotc2) + c1dotc2;
    double rightRate = c2tangentmag2 + (CGFloat)fabs(c1dotc2);
        
    // Transform the curves to use a new, shared t-parameter which is offset and scaled from the original, so that at t' = 0, the curves have the same value (this is the intersection that was passed in) and the same tangent vectors (due to the scaling)
    // T_left = T' * rightRate + leftParameter, T_right = T' * leftRate + rightParameter
    // therefore: T' = ( T_left - leftParameter ) / rightRate, T' = ( T_right - rightParameter ) / leftRate
    NSPoint c1[4], c2[4];
    affineSubstituteParameter(c1coeff, c1, rightRate, i->leftParameter);
    affineSubstituteParameter(c2coeff, c2, leftRate, i->rightParameter);
    double TsharedMin, TsharedMax;
    {
        // Transform the endpoints of the original curves (which are t=0 and t=1) into the new T' variable, so we know how far we want to extend the intersection
        double c1min = ( 0 - i->leftParameter ) / rightRate;
        double c1max = ( 1 - i->leftParameter ) / rightRate;
        double c2min = ( 0 - i->rightParameter ) / leftRate;
        double c2max = ( 1 - i->rightParameter ) / leftRate;
        
        // c1min...c1max and c2min...c2max define the T'-parameter ranges of the original curves. Curve 2's parameters might be reversed.
        OBASSERT(c1min <= c1max);
        if (c2min > c2max) { SWAP(c2min, c2max); }

        // compute the range that's wholly within both curves' ranges
        TsharedMin = MAX(c1min, c2min);
        TsharedMax = MIN(c1max, c2max);
        
       //  NSLog(@"T'[%g %g %g %g] --> (%g, %g)", c1min, c1max, c2min, c2max, TsharedMin, TsharedMax);
    }
    
    OBASSERT(TsharedMin <= EPSILON);
    OBASSERT(TsharedMax >= -EPSILON);
    
    double errVectorX[4], errVectorY[4];
    for(unsigned ix = 0; ix < 4; ix++) { errVectorX[ix] = c1[ix].x - c2[ix].x; errVectorY[ix] = c1[ix].y - c2[ix].y; } 
    
    // NSLog(@"errvec: origin=(%g,%g) deriv=(%g,%g)", errVectorX[0], errVectorY[0], evaluateCubicDerivative(errVectorX, 0), evaluateCubicDerivative(errVectorY, 0));
    
    // What we want to do is find the range around T'=0 (at most TsharedMin...TsharedMax) for which the error vector's magnitude is less than 'bloom'.
    // Solving this directly would involve a 6th-degree polynomial, which would be a PITA.
    // So instead we solve for the X and Y error components separately. This means that the interpretation of 'bloom' is orientation-dependent (by as much as sqrt(2)), but since bloom is only nonzero to account for roundoff anyway, I'm not worrying about that.
    
    // First, we can compute some loose bounds on the error vector components.
    BOOL nonnegligibleErrorX = looseCubicExceedsBounds(errVectorX, TsharedMin, TsharedMax, -bloom, bloom);
    BOOL nonnegligibleErrorY = looseCubicExceedsBounds(errVectorY, TsharedMin, TsharedMax, -bloom, bloom);
    if (!nonnegligibleErrorX && !nonnegligibleErrorX) {
        // The two cubics are equal, at least over the range and within the accuracy we care about.
        //NSLog(@"Approximately equal within T'=(%g ... %g)  coeffX=[%g %g %g %g] coeffY=[%g %g %g %g]",
        //      TsharedMin, TsharedMax, errVectorX[3], errVectorX[2], errVectorX[1], errVectorX[0], errVectorY[3], errVectorY[2], errVectorY[1], errVectorY[0]);
    }
    
    // Otherwise, call solveCubic() with some offset values, in order to find out when the error vector goes outside of the bloom box.
    if (nonnegligibleErrorX) {
        double original_x0 = errVectorX[0];
        errVectorX[0] = original_x0 + bloom;
        shrinkIntervalToRoots(errVectorX, &TsharedMin, &TsharedMax);
        errVectorX[0] = original_x0 - bloom;
        shrinkIntervalToRoots(errVectorX, &TsharedMin, &TsharedMax);
        errVectorX[0] = original_x0;
    }
    
    if (nonnegligibleErrorY) {
        double original_y0 = errVectorY[0];
        errVectorY[0] = original_y0 + bloom;
        shrinkIntervalToRoots(errVectorY, &TsharedMin, &TsharedMax);
        errVectorY[0] = original_y0 - bloom;
        shrinkIntervalToRoots(errVectorY, &TsharedMin, &TsharedMax);
        errVectorY[0] = original_y0;
    }

    // Transform our shrunken bounds back onto the original curves' t-parameters.
#if DEBUGGING_CURVE_INTERSECTIONS
    double oldLeft = i->leftParameter, oldRight = i->rightParameter;
#endif
    double newStart, newEnd;
    enum OAIntersectionAspect entryAspect, exitAspect;
    
    newStart = MAX(TsharedMin * rightRate + i->leftParameter, 0);
    newEnd = MIN(TsharedMax * rightRate + i->leftParameter, 1);
    OBASSERT(newStart >= 0-EPSILON);
    OBASSERT(newStart <= 1+EPSILON);
    OBASSERT(newEnd >= 0-EPSILON);
    OBASSERT(newEnd <= 1+EPSILON);
    newStart = CLAMP(newStart, 0, 1);
    newEnd = CLAMP(newEnd, 0, 1);
    i->leftParameter = newStart;
    i->leftParameterDistance = newEnd - newStart;
    OBASSERT(i->leftParameterDistance >= 0.0);
    
    // Compute the intersection aspects. We negate the offset when computing the exitAspect because lineAspect() wants the offset on the entering side of the other line, not the exiting side.
    entryAspect = lineAspect(evaluateCubicDerivativePt(c1coeff, newStart), evaluateCubic(errVectorX, TsharedMin),  evaluateCubic(errVectorY, TsharedMin));
    exitAspect = lineAspect(evaluateCubicDerivativePt(c1coeff, newEnd), - evaluateCubic(errVectorX, TsharedMax), - evaluateCubic(errVectorY, TsharedMax));
    
    newStart = TsharedMin * leftRate + i->rightParameter;
    newEnd = TsharedMax * leftRate + i->rightParameter;
    CDB(NSLog(@"T'(%g %g) --> t_right(%g %g) or 1+(%g %g)", TsharedMin, TsharedMax, newStart, newEnd, newStart-1, newEnd-1);)
    OBASSERT(newStart >= 0-EPSILON);
    OBASSERT(newStart <= 1+EPSILON);
    OBASSERT(newEnd >= 0-EPSILON);
    OBASSERT(newEnd <= 1+EPSILON);
    newStart = CLAMP(newStart, 0, 1);
    newEnd = CLAMP(newEnd, 0, 1);
    i->rightParameter = newStart;
    i->rightParameterDistance = newEnd - newStart;
    
    if (i->rightParameterDistance >= 0.0) {
        i->leftEntryAspect = entryAspect;
        i->leftExitAspect = exitAspect;
    } else {
        i->leftEntryAspect = - exitAspect;
        i->leftExitAspect = - entryAspect;
    }

#warning 64BIT: Check formatting arguments
    CDB(NSLog(@"Grazing extension: t'=(%g ... %g) --> left=%g%+g  right=%g%+g  (was left=%g right=%g) aspects %s-%s",
              TsharedMin, TsharedMax,
              i->leftParameter, i->leftParameterDistance, i->rightParameter, i->rightParameterDistance,
              oldLeft, oldRight,
              straspect(i->leftEntryAspect), straspect(i->leftExitAspect));)
    
    return YES;
}

// The inner loop of the curve-curve intersection algorithm. Curves are subdivided into segments and the segments are recursively compared. If a segment is flat enough, it can be treated as a line and intersected using intersectionsBetweenCurveAndLine(). If a segment is far enough away from other segments, it doesn't need to be compared at all.
// The previousResults parameter is scanned for previously-found grazing intersections, which we use to short-circuit subdivision inside the grazing region.
static unsigned intersectionsBetweenCurveAndCurveMonotonic(const NSPoint *c1coeff, const NSPoint *c2coeff,
                                                      double c1Low, double c1Size,
                                                      double c2Low, double c2Size,
                                                      struct intersectionInfo *results,
                                                      struct intersectionInfo *previousResults)
{
#if defined(DEBUGGING_CURVE_INTERSECTIONS)
    static int indent;
    for(int qq = 0; qq < indent; qq++)
        putchar(' ');
#endif
    
    // Step forward past any previousResults that aren't relevant to us (in terms of being a grazing extension that might cover us or one of our recursive subdivisions).
    while (previousResults < results) {
        // A previous result is irrelevant if its length is zero, or if it's wholly before our range of interest.
        // Both halves have to be irrelevant before we will skip past.
        // Note that the test for leftParameter is simpler because its distance is known to be nonnegative.
        
        if (previousResults->leftParameterDistance != 0 &&
            previousResults->leftParameter+previousResults->leftParameterDistance >= c1Low)
            break;
            
        if (previousResults->rightParameterDistance != 0 && 
            (previousResults->rightParameter >= c2Low || previousResults->rightParameter+previousResults->rightParameterDistance >= c2Low))
            break;

        previousResults ++;
    }
    
    // Check whether the previousResults cover the range we're investigating. If so, we can shortcircuit and return 0, because anything we return would be incorporated into the extended result anyway.
    {
        struct intersectionInfo *rcursor;
        BOOL c1Covered, c2Covered;
        c1Covered = c2Covered = NO;
        
        // if (previousResults < results)
        //    printf("[%dp", results - previousResults);
        
        for (rcursor = previousResults; rcursor < results; rcursor++) {
            BOOL ll, rr;
            ll = pdrangeCoversPDrange(rcursor->leftParameter, rcursor->leftParameterDistance, c1Low, c2Size);
            rr = drangeCoversPDrange(rcursor->rightParameter, rcursor->rightParameterDistance, c2Low, c2Size);
            //putchar(' ');
            //if (ll) putchar('l');
            //if (rr) putchar('r');
            //if (!ll && !rr) putchar('.');
            c1Covered = c1Covered || ll;
            c2Covered = c2Covered || rr;
            
            if (c1Covered && c2Covered) {
                // Note that c1Covered and c2Covered don't necessarily come from the same previous result.
                //printf("] Skipping due to grazing extension\n");
                return 0;
            }
        }
        
        //if (previousResults < results)
        //    putchar(']'), putchar(' ');
    }
    
    // The unmodified curve is passed in. Each call re-parameterizes it for the segment of interest.
    NSPoint left[4], right[4];
    splitParameterizedCurve(c1coeff, left, c1Low, c1Size);
    splitParameterizedCurve(c2coeff, right, c2Low, c2Size);
    
    // The simplest case is if the two curves' bounding boxes don't even intersect.
    if (!parameterizedMonotonicCurveBoundsIntersect(left, right)) {
        CDB(printf(" found 0 via nonintersection\n");)
        // The loose bounding boxes don't intersect.
        return 0;
    }

    // Check whether c1 or c2 is close enough to a straight line for our purposes.
    // The error vector of the straight-line approximation is t * (t-1) * (p[2] + p[3]*(t+1)) for a parameterized curve p[0..3].
    // The first pair of terms can't exceed 1/4, and the magnitude of the last pair can't exceed |p[2]+p[3]|+|p[3]| over the range 0<=t<=1.
    // So we use this as an easy to compute upper bound on the error. Note that this is a vector error: a Bezier curve could be a straight line with a nonuniform 't' parameter and not count as straight by this measure. We need to use the vector error, or else we'll compute incorrect t-parameter values for the intersections (and eventually subdivide curves in the wrong places).
    double error_bound_left, error_bound_right;
    
    error_bound_left = ( vecmag(left[2].x+left[3].x, left[2].y+left[3].y) + vecmag(left[3].x, left[3].y) ) / 4;
    error_bound_right = ( vecmag(right[2].x+right[3].x, right[2].y+right[3].y) + vecmag(right[3].x, right[3].y) ) / 4;
    
#warning 64BIT: Check formatting arguments
    CDB(printf("errbs=(%g,%g)", error_bound_left, error_bound_right);)
    
    if (error_bound_left < FLATNESS || error_bound_right < FLATNESS) {
        unsigned found, fixup;
        NSPoint l2[2];
        
        // Yup, looks like a line. Compute the parameterized line representation and use that.
        if (error_bound_right <= error_bound_left) {
            // The right-hand curve is flatter than the left-hand curve, so linearizing it loses less accuracy.
            l2[0] = right[0];
            l2[1].x = right[1].x + right[2].x + right[3].x;
            l2[1].y = right[1].y + right[2].y + right[3].y;
            found = intersectionsBetweenCurveAndLine(left, l2, results);
            CDB(printf(" found %u via right linearization", found);)
        } else {
            // Same as above, but the left-hand curve was flatter.
            l2[0] = left[0];
            l2[1].x = left[1].x + left[2].x + left[3].x;
            l2[1].y = left[1].y + left[2].y + left[3].y;
            found = intersectionsBetweenCurveAndLine(right, l2, results);
            for(fixup = 0; fixup < found; fixup++)
                reverseSenseOfIntersection(&(results[fixup]));
            CDB(printf(" found %u via left  linearization", found);)
        }
    
        // TODO: We could probably do a newton-raphson step here to get a few more digits of accuracy?

        CDB(printf(": (%g%+g, %g%+g)\n", l2[0].x, l2[1].x, l2[0].y, l2[1].y);)
        
        for(fixup = 0; fixup < found; fixup++) {
            results[fixup].leftParameter = results[fixup].leftParameter * c1Size + c1Low;
            results[fixup].leftParameterDistance *= c1Size;
            results[fixup].rightParameter = results[fixup].rightParameter * c2Size + c2Low;
            results[fixup].rightParameterDistance *= c2Size;
                        
            extendGrazingIntersection(c1coeff, c2coeff, &(results[fixup]), GRAZING_CURVE_BLOOM_DISTANCE);
        }
        
        return found;
    }
    
    // Finally, fall back on breaking up the curves into halves, and checking each pair of halves.
    
#if defined(DEBUGGING_CURVE_INTERSECTIONS)
    printf(" recursing\n");
    indent ++;
#endif
    
    unsigned foundLow, foundHigh, foundFirstHalf, foundSecondHalf, foundTotal;
    
    // Subdivide each curve, and find intersections with each half. Eventually we'll either find a fragment that's flat enough to treat as a line, or we'll discover it's outside of the other curve's bounding box.
    foundLow  = intersectionsBetweenCurveAndCurveMonotonic(c1coeff, c2coeff, c1Low, c1Size / 2, c2Low, c2Size/2, results, previousResults);
    foundHigh = intersectionsBetweenCurveAndCurveMonotonic(c1coeff, c2coeff, c1Low, c1Size / 2, c2Low + c2Size/2, c2Size/2, results + foundLow, previousResults);
    foundFirstHalf = mergeSortIntersectionInfo(results, foundLow, foundHigh, -1, c2Low + c2Size/2);
#if defined(DEBUGGING_CURVE_INTERSECTIONS)
    unsigned f0 = foundLow, fh0 = foundHigh;
#endif
        
    foundLow  = intersectionsBetweenCurveAndCurveMonotonic(c1coeff, c2coeff, c1Low + c1Size / 2, c1Size / 2, c2Low, c2Size/2, results + foundFirstHalf, previousResults);
    foundHigh = intersectionsBetweenCurveAndCurveMonotonic(c1coeff, c2coeff, c1Low + c1Size / 2, c1Size / 2, c2Low + c2Size/2, c2Size/2, results + foundFirstHalf + foundLow, previousResults);
    foundSecondHalf = mergeSortIntersectionInfo(results + foundFirstHalf, foundLow, foundHigh, -1, c2Low + c2Size/2);
    foundTotal = mergeSortIntersectionInfo(results, foundFirstHalf, foundSecondHalf, c1Low + c1Size / 2, -1);

#if defined(DEBUGGING_CURVE_INTERSECTIONS)
    indent --;
    
    for(int qq = 0; qq < indent; qq++)
        putchar(' ');
    printf("found %u %u %u %u -> %u %u -> %u\n", f0, fh0, foundLow, foundHigh, foundFirstHalf, foundSecondHalf, foundTotal);
#endif
    
    OBASSERT(foundTotal <= MAX_INTERSECTIONS_PER_ELT_PAIR);
    
    return foundTotal;
}

struct curveSegment {
    double start;
    double size;
};

/* Given a parameterized cubic curve, this computes the segments (in order) of the curve such that each segment is monotonic in X and Y, that is, it does not turn back on itself. This makes the logic in intersectionsBetweenCurveAndCurveMonotonic() simpler because the bounding box of a curve segment becomes just the box of its endpoints. */
static unsigned computeCurveSegments(const NSPoint *coeff, struct curveSegment segments[5])
{
    double tvalues[4];
    double c[4];
    unsigned tvcount, tvindex;
    unsigned segcount;
    double tStart, nextT;
    
    c[0] = coeff[0].x;
    c[1] = coeff[1].x;
    c[2] = coeff[2].x;
    c[3] = coeff[3].x;
    tvcount = findCubicExtrema(c, tvalues);
    c[0] = coeff[0].y;
    c[1] = coeff[1].y;
    c[2] = coeff[2].y;
    c[3] = coeff[3].y;
    tvcount += findCubicExtrema(c, tvalues + tvcount);
    
    OBASSERT(tvcount <= 4); // At most two extrema per axis, for a total of 4
    
    segcount = 0;
    tStart = 0;

    while (tStart < 1.0) {
        nextT = 1.0f;
        for(tvindex = 0; tvindex < tvcount; tvindex ++) {
            if (tvalues[tvindex] > tStart && tvalues[tvindex] < nextT)
                nextT = tvalues[tvindex];
        }
        segments[segcount++] = (struct curveSegment){ .start = tStart, .size = nextT - tStart };
        tStart = nextT;
    }

#if DEBUGGING_CURVE_INTERSECTIONS
    {
        NSMutableString *s = [NSMutableString string];
        for(unsigned q = 0; q < segcount; q++)
            [s appendFormat:@"  %g%+g", segments[q].start, segments[q].size];
        NSLog(@"Curve segments(%d): %@", segcount, s);
    }
#endif
    
    return segcount;
}

/*
 Given a non-parameterized cubic curve (i.e, control points), compute the tight bounding box of the curve.
 This is equivalent to parameterizing it, calling computeCurveSegments() above, and then computing the bounding box of each segment. (But more efficient.)
 The bounding box in 'r' is extended to include the bounds. If the box is modified (incl. if it was a zero rect to start with) then this function returns YES, otherwise NO.
 The input control points are in the order (start, c1, c2, end).
*/
#define INCLUDE(minC, maxC, aC, clearance) do { double value = (aC); \
    if (value-clearance < minC) { /* NSLog(@"%g < %g (%s)", value-clearance, minC, #minC); */ minC = value-clearance; modified = YES; } \
    if (value+clearance > maxC) { /* NSLog(@"%g > %g (%s)", value+clearance, maxC, #maxC); */ maxC = value+clearance; modified = YES; } \
    } while(0)

static BOOL inline isIncluded(double min, double max, double p, double clearance)
{
    return (p-clearance >= min && p+clearance <= max);
}

BOOL tightBoundsOfCurveTo(NSRect *rectp, NSPoint startPoint, NSPoint controlPoint1, NSPoint controlPoint2, NSPoint endPoint, CGFloat sideClearance)
{
    BOOL modified;
    double minX, maxX, minY, maxY;
    
    if (rectp->size.width <= 0 || rectp->size.height <= 0) {
        /* If passed an empty rect, initialize it from our start and end points */
        minX = MIN(startPoint.x, endPoint.x);
        minY = MIN(startPoint.y, endPoint.y);
        maxX = MAX(startPoint.x, endPoint.x);
        maxY = MAX(startPoint.y, endPoint.y);
        modified = YES;
    } else {
        /* convert input rect to min/max form */
        minX = NSMinX(*rectp);
        minY = NSMinY(*rectp);
        maxX = NSMaxX(*rectp);
        maxY = NSMaxY(*rectp);
        modified = NO;
        
        /* Make sure the endpoints are included */
        INCLUDE(minX, maxX, startPoint.x, 0);
        INCLUDE(minX, maxX, endPoint.x, 0);
        INCLUDE(minY, maxY, startPoint.y, 0);
        INCLUDE(minY, maxY, endPoint.y, 0);
    }
        
    /* Short-circuit if the control points are in the rect */
    /* (this is pretty common in practice) */
    if(isIncluded(minX, maxX, controlPoint1.x, sideClearance) &&
       isIncluded(minX, maxX, controlPoint2.x, sideClearance) &&
       isIncluded(minY, maxY, controlPoint1.y, sideClearance) &&
       isIncluded(minY, maxY, controlPoint2.y, sideClearance)) {
        goto finis;
    }
    
    /* Convert to parametric form and find the extreme points using findCubicExtrema() */
    /* Note that findCubicExtrema() will happily return extremes outside the range [0,1], which we want to ignore */
    NSPoint coefficientPoints[4];
    _parameterizeCurve(coefficientPoints, startPoint, endPoint, controlPoint1, controlPoint2);
    
    double  coefficients[4], tvalues[2];
    unsigned tvcount;
    
    /* Check the x-extrema */
    coefficients[0] = coefficientPoints[0].x;
    coefficients[1] = coefficientPoints[1].x;
    coefficients[2] = coefficientPoints[2].x;
    coefficients[3] = coefficientPoints[3].x;
    tvcount = findCubicExtrema(coefficients, tvalues);
    if (tvcount >= 1 && tvalues[0] > 0 && tvalues[0] < 1)
        INCLUDE(minX, maxX, evaluateCubic(coefficients, tvalues[0]), sideClearance);
    if (tvcount >= 2 && tvalues[1] > 0 && tvalues[1] < 1)
        INCLUDE(minX, maxX, evaluateCubic(coefficients, tvalues[1]), sideClearance);
    
    /* and the y-extrema */
    coefficients[0] = coefficientPoints[0].y;
    coefficients[1] = coefficientPoints[1].y;
    coefficients[2] = coefficientPoints[2].y;
    coefficients[3] = coefficientPoints[3].y;
    tvcount = findCubicExtrema(coefficients, tvalues);
    if (tvcount >= 1 && tvalues[0] > 0 && tvalues[0] < 1)
        INCLUDE(minY, maxY, evaluateCubic(coefficients, tvalues[0]), sideClearance);
    if (tvcount >= 2 && tvalues[1] > 0 && tvalues[1] < 1)
        INCLUDE(minY, maxY, evaluateCubic(coefficients, tvalues[1]), sideClearance);
    
finis:
    if (modified) {
        /* convert back to origin+size representation for the caller */
        rectp->origin.x = (CGFloat)minX;
        rectp->origin.y = (CGFloat)minY;
        rectp->size.width = (CGFloat)(maxX - minX);
        rectp->size.height = (CGFloat)(maxY - minY);
        return YES;
    } else
        return NO;
}

static unsigned coalesceExtendedIntersections(struct intersectionInfo *results, unsigned found)
{
    unsigned i, j;
    
    for(i = 0; i+1 < found; i++) {
        for(j = i+1; j < found; j++) {
            if (results[j].leftParameter > EPSILON+(results[i].leftParameter+results[i].leftParameterDistance))
                break;  // This is the common case
            
            if (drangeIntersectsDrange(results[i].leftParameter, results[i].leftParameterDistance, results[j].leftParameter, results[j].leftParameterDistance) &&
                drangeIntersectsDrange(results[i].rightParameter, results[i].rightParameterDistance, results[j].rightParameter, results[j].rightParameterDistance) &&
                signbit(results[i].rightParameterDistance) == signbit(results[j].rightParameterDistance)) {
                
#warning 64BIT: Check formatting arguments
                CDB(printf("combining %d:[%g%+g %g%+g] %s-%s and %d:[%g%+g %g%+g] %s-%s ",
                           i, results[i].leftParameter, results[i].leftParameterDistance, results[i].rightParameter, results[i].rightParameterDistance,
                           straspect(results[i].leftEntryAspect), straspect(results[i].leftExitAspect),
                           j, results[j].leftParameter, results[j].leftParameterDistance, results[j].rightParameter, results[j].rightParameterDistance,
                           straspect(results[j].leftEntryAspect), straspect(results[j].leftExitAspect)));
                                
                combinePDranges(&(results[i].leftParameter), &(results[i].leftParameterDistance),
                                results[i].leftParameter, results[i].leftParameterDistance,
                                results[j].leftParameter, results[j].leftParameterDistance);
                
                // This is combineDranges(), but we need to carry the intersection aspects along with the combined ranges
                double  newStart, newEnd;
                if (results[i].rightParameterDistance >= 0) {
                    if (results[i].rightParameter > results[j].rightParameter) {
                        newStart = results[j].rightParameter;
                        results[i].leftEntryAspect = results[j].leftEntryAspect;
                    } else {
                        newStart = results[i].rightParameter;
                    }
                    if ((results[i].rightParameter+results[i].rightParameterDistance) < (results[j].rightParameter+results[j].rightParameterDistance)) {
                        newEnd = (results[j].rightParameter+results[j].rightParameterDistance);
                        results[i].leftExitAspect = results[j].leftExitAspect;
                    } else {
                        newEnd = (results[i].rightParameter+results[i].rightParameterDistance);
                    }
                } else {
                    if (results[i].rightParameter < results[j].rightParameter) {
                        newStart = results[j].rightParameter;
                        results[i].leftEntryAspect = results[j].leftEntryAspect;
                    } else {
                        newStart = results[i].rightParameter;
                    }
                    if ((results[i].rightParameter+results[i].rightParameterDistance) > (results[j].rightParameter+results[j].rightParameterDistance)) {
                        newEnd = (results[j].rightParameter+results[j].rightParameterDistance);
                        results[i].leftExitAspect = results[j].leftExitAspect;
                    } else {
                        newEnd = (results[i].rightParameter+results[i].rightParameterDistance);
                    }
                }
                results[i].rightParameter = newStart;
                results[i].rightParameterDistance = newEnd - newStart;
                
                CDB(printf("into [%g%+g %g%+g] %s-%s\n", results[i].leftParameter, results[i].leftParameterDistance, results[i].rightParameter, results[i].rightParameterDistance, straspect(results[i].leftEntryAspect), straspect(results[i].leftExitAspect));)
                    
#warning 64BIT: Inspect use of sizeof
                memmove(&(results[j]), &(results[j+1]), sizeof(*results) * (found - (j+1)));
                found --;
                j --;
            }
        }
    }
    
    return found;
}


// This is the entry point for curve-curve intersection. Break up each curve into monotonic segments. Compute all intersections, including finding grazing regions. Then compute the aspect of the grazing regions (after any coalescing has happened).
unsigned intersectionsBetweenCurveAndCurve(const NSPoint *c1coefficients, const NSPoint *c2coefficients, struct intersectionInfo *results)
{
    struct curveSegment leftSegments[5], rightSegments[5];
    unsigned leftSegmentCount, rightSegmentCount;
    unsigned leftSegmentIndex, rightSegmentIndex;
    unsigned found;
    
    /* Break the input curves into segments (up to five) so that each segment is monotonic in x and y in the range t=0...1. */
    leftSegmentCount = computeCurveSegments(c1coefficients, leftSegments);
    rightSegmentCount = computeCurveSegments(c2coefficients, rightSegments);
    
    found = 0;
    for(leftSegmentIndex = 0; leftSegmentIndex < leftSegmentCount; leftSegmentIndex ++) {
        for(rightSegmentIndex = 0; rightSegmentIndex < rightSegmentCount; rightSegmentIndex ++) {
            unsigned foundMore;
            // printf("Segment %d/%d %d/%d\n", leftSegmentIndex, leftSegmentCount, rightSegmentIndex, rightSegmentCount);
            foundMore = intersectionsBetweenCurveAndCurveMonotonic(c1coefficients, c2coefficients,
                                                                   leftSegments[leftSegmentIndex].start, leftSegments[leftSegmentIndex].size,
                                                                   rightSegments[rightSegmentIndex].start, rightSegments[rightSegmentIndex].size,
                                                                   results + found, results);
            found = mergeSortIntersectionInfo(results, found, foundMore, leftSegments[leftSegmentIndex].start, rightSegments[rightSegmentIndex].start);
        }
        found = coalesceExtendedIntersections(results, found);
    }
    
    OBASSERT(found <= MAX_INTERSECTIONS_PER_ELT_PAIR);
    return found;
}

- (BOOL)_curvedIntersection:(CGFloat *)length time:(CGFloat *)time curve:(NSPoint *)c line:(NSPoint *)a
{
    NSInteger i;
    double  cubic[4];
    double  roots[3];
    unsigned dummy[3];
    NSInteger count;
    CGFloat minT = 1.1f;
    BOOL foundOne = NO;
    
    for(i=0;i<4;i++) {
        cubic[i] = c[i].x * a[1].y - c[i].y * a[1].x;
    }
    cubic[0] -= (a[0].x * a[1].y - a[0].y * a[1].x);
    
    count = _solveCubic(cubic, roots, dummy);
    
    for(i=0;i<count;i++) {
        CGFloat u = (CGFloat)roots[i];
        CGFloat t;
        
        if (u < -0.0001 || u > 1.0001) {
            continue;
        }
        if (isnan(u)) {
            continue;
        }
        
        // Used to be (a[1].x == 0), but that caused problems if a[1].x was very close to zero.
        // Instead we use whichever is larger.
        if (fabs(a[1].x) < fabs(a[1].y)) {
            t = c[0].y + u * (c[1].y + u * (c[2].y + u * c[3].y));
            t -= a[0].y;
            t /= a[1].y;
        } else {
            t = c[0].x + u * (c[1].x + u * (c[2].x + u * c[3].x));
            t -= a[0].x;
            t /= a[1].x;
        }
        if (t < -0.0001 || t > 1.0001) {
            continue;
        }
        
        if (t < minT) {
            foundOne = YES;
            minT = t;
            *time = u;
        }
    }
    
    if (foundOne) {
        if (minT < 0)
            minT = 0;
        else if (minT > 1)
            minT = 1;
        *length = minT;
        return YES;
    }
    
    return NO;
}

BOOL initializeSubpathWalkingState(struct subpathWalkingState *s, NSBezierPath *p, NSInteger startIndex, BOOL implicitClosepath)
{
    NSInteger pathElementCount = [p elementCount];
    
    // Fail if the startIndex is past the end. Also fail if the startIndex points to the last element, because the only valid 1-element subpath is a single moveto, and we ignore those.
    if (startIndex >= (pathElementCount-1)) {
        return NO;
    }
    
    s->pathBeingWalked = p;
    s->elementCount = pathElementCount;
    s->possibleImplicitClosepath = implicitClosepath;
    s->what = [p elementAtIndex:startIndex associatedPoints:s->points];
    if (s->what != NSMoveToBezierPathElement) {
        OBASSERT_NOT_REACHED("Bezier path element should be NSMoveToBezierPathElement but isn't");
        return NO;
    }
    s->startPoint = s->points[0];
    s->currentElt = startIndex;
    
    return YES;
}

BOOL nextSubpathElement(struct subpathWalkingState *s)
{
    switch(s->what) {
        default:
            OBASSERT_NOT_REACHED("Unknown NSBezierPathElement");
            /* FALL THROUGH */
        case NSClosePathBezierPathElement:
            return NO;
            
        case NSMoveToBezierPathElement:
            /* The first element of the path */
            break;
            
        case NSLineToBezierPathElement:
            s->points[0] = s->points[1];  // update currentpoint
            break;
        case NSCurveToBezierPathElement:
            s->points[0] = s->points[3];  // update currentpoint
            break;
    }
    
    s->currentElt ++;
    if (s->currentElt >= s->elementCount) {
        // Whoops. An unterminated path. Do the implicit closepath.
        if (s->possibleImplicitClosepath) {
            s->what = NSClosePathBezierPathElement;
            s->points[1] = s->startPoint;
        } else {
            // An open path; we're done.
            s->currentElt --;
            return NO;
        }
    } else {
        s->what = [s->pathBeingWalked elementAtIndex:s->currentElt associatedPoints:(s->points + 1)];    
        switch(s->what) {
            case NSClosePathBezierPathElement:
                s->possibleImplicitClosepath = NO;
                s->elementCount = s->currentElt + 1;
                s->points[1] = s->startPoint;
                break;
                
            default:
                OBASSERT_NOT_REACHED("Unknown NSBezierPathElement");
                /* FALL THROUGH */
            case NSMoveToBezierPathElement:
                // An unterminated subpath.
                s->elementCount = s->currentElt; // The moveto we just extracted is part of the next subpath, not this one.
                if (s->possibleImplicitClosepath) {
                    // Do the implicit closepath.
                    s->what = NSClosePathBezierPathElement;
                    s->points[1] = s->startPoint;
                } else {
                    // Back up.
                    s->currentElt --;
                    return NO;
                }
                break;
                
            case NSLineToBezierPathElement:
            case NSCurveToBezierPathElement:
                /* These require no special actions */
                break;
        }
    }
    
    return YES;
}

// This predicts whether nextSubpathElement() would return YES or NO on the next call
BOOL hasNextSubpathElement(struct subpathWalkingState *s)
{
    if (s->what == NSClosePathBezierPathElement)
        return NO;
    
    NSBezierPathSegmentIndex nextEltIndex = s->currentElt + 1;
    if (!(s->possibleImplicitClosepath)) {
        if (nextEltIndex >= s->elementCount) {
            return NO;
        } else {
            NSBezierPathElement nextOp = [s->pathBeingWalked elementAtIndex:nextEltIndex];
            if (nextOp == NSMoveToBezierPathElement)
                return NO;
        }
    }
    
    return YES;
}

void repositionSubpathWalkingState(struct subpathWalkingState *s, NSInteger toIndex)
{
    if (toIndex == 0) {
        initializeSubpathWalkingState(s, s->pathBeingWalked, 0, s->possibleImplicitClosepath);
        return;
    }
    
    NSBezierPathElement previousElt = [s->pathBeingWalked elementAtIndex:toIndex-1 associatedPoints:(s->points)];
    switch(previousElt) {
        case NSLineToBezierPathElement:
        case NSMoveToBezierPathElement:
            break;
        case NSCurveToBezierPathElement:
            s->points[0] = s->points[2];
            break;
        default:
            OBASSERT_NOT_REACHED("repositionSubpathWalkingState() called after wrong elt type");
            break;
    }

    s->currentElt = toIndex;
    if (s->currentElt == s->elementCount && s->possibleImplicitClosepath)
        s->what = NSClosePathBezierPathElement;
    else
        s->what = [s->pathBeingWalked elementAtIndex:s->currentElt associatedPoints:(s->points + 1)];
    if (s->what == NSClosePathBezierPathElement) {
        s->points[1] = s->startPoint;
    }
    
    OBASSERT(s->what == NSLineToBezierPathElement || s->what == NSCurveToBezierPathElement || s->what == NSClosePathBezierPathElement);
}

static BOOL _straightLineIntersectsRect(const NSPoint *a, NSRect rect) {
    // PENDING: needs some work...
    if (NSPointInRect(a[0], rect)) {
        return YES;
    }
    if (a[1].x != 0) {
        double t = (NSMinX(rect) - a[0].x)/a[1].x;
        double y;
        if (t >= 0 && t <= 1) {
            y = t * a[1].y + a[0].y;
            if (y >= NSMinY(rect) && y < NSMaxY(rect)) {
                return YES;
            }
        }
        t = (NSMaxX(rect) - a[0].x)/a[1].x;
        if (t >= 0 && t <= 1) {
            y = t * a[1].y + a[0].y;
            if (y >= NSMinY(rect) && y < NSMaxY(rect)) {
                return YES;
            }
        }
    }
    if (a[1].y != 0) {
        double t = (NSMinY(rect) - a[0].y)/a[1].y;
        double x;
        if (t >= 0 && t <= 1) {
            x = t * a[1].x + a[0].x;
            if (x >= NSMinX(rect) && x < NSMaxX(rect)) {
                return YES;
            }
        }
        t = (NSMaxY(rect) - a[0].y)/a[1].y;
        if (t >= 0 && t <= 1) {
            x = t * a[1].x + a[0].x;
            if (x >= NSMinX(rect) && x < NSMaxX(rect)) {
                return YES;
            }
        }
    }
//    } else {
//        if (a[0].x < NSMinX(rect) || a[0].x > NSMaxX(rect)) {
//            return NO;
//        }
//        if (a[0].y < NSMinY(rect)) {
//            if ((a[0].y + a[1].y) >= NSMinY(rect)) {
//                return YES;
//            }
//        } else if (a[0].y <= NSMaxY(rect)) {
//            return YES;
//        }
//    }
    return NO;
} 

#if 0
// Not used at the moment
static void _splitCurve(const NSPoint *c, NSPoint *left, NSPoint *right) {
    left[0] = c[0];
    left[1].x = 0.5 * c[1].x;
    left[1].y = 0.5 * c[1].y;
    left[2].x = 0.25 * c[2].x;
    left[2].y = 0.25 * c[2].y;
    left[3].x = 0.125 * c[3].x;
    left[3].y = 0.125 * c[3].y;

    right[0].x = left[0].x + left[1].x + left[2].x + left[3].x;
    right[0].y = left[0].y + left[1].y + left[2].y + left[3].y;
    right[1].x = 3 * left[3].x + 2 * left[2].x + left[1].x;
    right[1].y = 3 * left[3].y + 2 * left[2].y + left[1].y;
    right[2].x = 3 * left[3].x + left[2].x;
    right[2].y = 3 * left[3].y + left[2].y;
    right[3] = left[3];
}
#endif

static void splitParameterizedCurveLeft(const NSPoint *c, NSPoint *left)
{
    // This is just a substitution of t' = t / 2
    left[0].x = c[0].x;
    left[0].y = c[0].y;
    left[1].x = c[1].x / 2;
    left[1].y = c[1].y / 2;
    left[2].x = c[2].x / 4;
    left[2].y = c[2].y / 4;
    left[3].x = c[3].x / 8;
    left[3].y = c[3].y / 8;
}

static void splitParameterizedCurveRight(const NSPoint *c, NSPoint *right)
{
    // This is just a substitution of t' = (t + 1) / 2
    right[0].x = c[0].x + c[1].x/2 + c[2].x/4 + c[3].x/8;
    right[0].y = c[0].y + c[1].y/2 + c[2].y/4 + c[3].y/8;
    right[1].x =          c[1].x/2 + c[2].x/2 + c[3].x*3/8;
    right[1].y =          c[1].y/2 + c[2].y/2 + c[3].y*3/8;
    right[2].x =                     c[2].x/4 + c[3].x*3/8;
    right[2].y =                     c[2].y/4 + c[3].y*3/8;
    right[3].x =                                c[3].x/8;
    right[3].y =                                c[3].y/8;
}

static BOOL _curvedLineIntersectsRect(const NSPoint *c, NSRect rect, CGFloat tolerance) {
    NSRect bounds = _parameterizedCurveBounds(c);
    if (NSIntersectsRect(rect, bounds)) {
        if (bounds.size.width <= tolerance ||
            bounds.size.height <= tolerance) {
                return YES;
        } else {
            NSPoint half[4];
            splitParameterizedCurveLeft(c, half);
            if (_curvedLineIntersectsRect(half, rect, tolerance))
                return YES;
            splitParameterizedCurveRight(c, half);
            if (_curvedLineIntersectsRect(half, rect, tolerance))
                return YES;
        }
    }
    return NO;
}

- (BOOL)_curvedLineHit:(NSPoint)point startPoint:(NSPoint)startPoint endPoint:(NSPoint)endPoint controlPoint1:(NSPoint)controlPoint1 controlPoint2:(NSPoint)controlPoint2 position:(CGFloat *)position padding:(CGFloat)padding
{
    // find the square of the distance between the point and a point
    // on the curve (u).
    // use newtons method to approach the minumum u.
    NSPoint a[4];     // our regular coefficients
    double  c[7];  // a cubic squared gives us 7 coefficients
    double  u, bestU;

    double  tolerance = padding + [self lineWidth] / 2;
    double  delta, minDelta;
    NSInteger i;
        
//    if (tolerance < 3) {
//        tolerance = 3;
//    }
    
    tolerance *= tolerance;

    _parameterizeCurve(a, startPoint, endPoint, controlPoint1, controlPoint2);
    
    delta = a[0].x - point.x;
    c[0] = delta * delta;
    delta = a[0].y - point.y;
    c[0] += delta * delta;
    c[1] = 2 * ((a[0].x - point.x) * a[1].x + (a[0].y - point.y) * a[1].y);
    c[2] = a[1].x * a[1].x + a[1].y * a[1].y +
        2 * (a[2].x * (a[0].x - point.x) + a[2].y * (a[0].y - point.y));
    c[3] = 2 * (a[1].x * a[2].x + (a[0].x - point.x) * a[3].x +
                a[1].y * a[2].y + (a[0].y - point.y) * a[3].y);
    c[4] = a[2].x * a[2].x + a[2].y * a[2].y +
      2 * (a[1].x * a[3].x + a[1].y * a[3].y);
    c[5] = 2.0f * (a[2].x * a[3].x + a[2].y * a[3].y);
    c[6] = a[3].x * a[3].x + a[3].y * a[3].y;


    // Estimate a starting U
    if (endPoint.x < startPoint.x) {
        u = point.x - endPoint.x;
    } else {
        u = point.x - startPoint.x;
    }
    
    delta = fabs(startPoint.x - point.x) + fabs(endPoint.x - point.x);
    delta += fabs(startPoint.y - point.y) + fabs(endPoint.y - point.y);

    if (endPoint.y < startPoint.y) {
        u += point.y - endPoint.y;
        delta += startPoint.y - endPoint.y;
    } else {
        u += point.y - startPoint.y;
        delta += endPoint.y - startPoint.y;
    }

    u /= delta;
    if (u < 0) {
        u = 0;
    } else if (u > 1) {
        u = 1;
    }

    // Iterate while adjust U with our error function

    // NOTE: Sadly, Newton's method becomes unstable as we approach the solution.  Also, the farther away from the curve, the wider the oscillation will be.
    // To get around this, we're keeping track of our best result, adding a few more iterations, and damping our approach.
    minDelta = 100000;
    bestU = u;
    
    for(i=0;i< 12;i++) {
        delta = (((((c[6] * u + c[5]) * u + c[4]) * u + c[3]) * u + c[2]) * u + c[1]) * u + c[0];
        if (delta < minDelta) {
            minDelta = delta;
            bestU = u;
        }

        if (i==11 && minDelta <= tolerance) {
            *position = (float)bestU;
            return YES;
        } else {
            double  slope = ((((( 6 * c[6] * u + 5 * c[5]) * u + 4 * c[4]) * u + 3 * c[3]) * u + 2 * c[2]) * u + c[1]);
            double  deltaU = delta/slope;

            if ((u==0 && delta > 0) || (u==1 && delta < 0)) {
                *position = (float)bestU;
                return minDelta <= tolerance;
            }
            u -= 0.75f * deltaU; // Used to be just deltaU, but we're damping it a bit
            if (u<0.0) {
                u = 0.0f;
            }
            if (u>1.0) {
                u = 1.0f;
            }
        }
    }

    return NO;
}

- (BOOL)_straightLineIntersection:(CGFloat *)length time:(CGFloat *)time segment:(NSPoint *)s line:(const NSPoint *)l {
    // PENDING: should optimize this for the most common cases (s[1] == 0);
    double u;
    double t;
    
    if (ABS(s[1].x) < 0.001) {
        if (ABS(s[1].y) < 0.001) {
            // This is a zero length line, currently generated by rounded rectangles
            // NOTE: should fix rounded rectangles
            return NO;
        }
        if (ABS(l[1].x) < 0.001) {
            return NO;
        }
		s[1].x = 0;
    } else if (ABS(s[1].y) < 0.001) {
        if (ABS(l[1].y) < 0.001) {
            return NO;
        }
		s[1].y = 0;
    } 
    
    u = (s[1].y * s[0].x - s[1].x * s[0].y) - (s[1].y * l[0].x - s[1].x * l[0].y);
    u /= (s[1].y * l[1].x - s[1].x * l[1].y);
    if (u < -0.0001 || u > 1.0001) {
        return NO;
    }
    if (s[1].x == 0) {
        t = (l[1].y * u + (l[0].y - s[0].y)) / s[1].y;
    } else {
        t = (l[1].x * u + (l[0].x - s[0].x)) / s[1].x;
    }
    if (t < -0.0001 || t > 1.0001 || isnan(t)) {
        return NO;
    }
    
    *length = (CGFloat)u;
    *time = (CGFloat)t;
    return YES;
}

- (BOOL)_straightLineHit:(NSPoint)startPoint :(NSPoint)endPoint :(NSPoint)point  :(CGFloat *)position padding:(CGFloat)padding {
    NSPoint delta;
    NSPoint vector;
    NSPoint linePoint;
    CGFloat length;
    CGFloat dotProduct;
    CGFloat distance;
    CGFloat tolerance = padding + [self lineWidth]/2;
    
//    if (tolerance < 3) {
//        tolerance = 3;
//    }
    
    delta.x = endPoint.x - startPoint.x;
    delta.y = endPoint.y - startPoint.y;
    length = sqrt(delta.x * delta.x + delta.y * delta.y);
    delta.x /=length;
    delta.y /=length;

    vector.x = point.x - startPoint.x;
    vector.y = point.y - startPoint.y;

    dotProduct = vector.x * delta.x + vector.y * delta.y;

    linePoint.x = startPoint.x + delta.x * dotProduct;
    linePoint.y = startPoint.y + delta.y * dotProduct;

    delta.x = point.x - linePoint.x;
    delta.y = point.y - linePoint.y;

    // really the distance squared
    distance = delta.x * delta.x + delta.y * delta.y;
    
    if (distance < (tolerance * tolerance)) {
        *position = dotProduct/length;
        if (*position >= 0 && *position <=1) {
            return YES;
        }
    }
    
    return NO;
}

- (NSPoint)_endPointForSegment:(NSInteger)i;
{
    NSPoint points[3];
    NSBezierPathElement element = [self elementAtIndex:i associatedPoints:points];
    switch(element) {
        case NSCurveToBezierPathElement:
            return points[2];
        case NSClosePathBezierPathElement:
            /* element = */ [self elementAtIndex:0 associatedPoints:points];
            /* FALL THROUGH */
        case NSMoveToBezierPathElement:
        case NSLineToBezierPathElement:
            return points[0];
    }
    return NSZeroPoint;
}

@end

#pragma mark CoreGraphics path functions

void OACGAddRoundedRect(CGContextRef context, NSRect rect, CGFloat minyLeft, CGFloat minyRight, CGFloat maxyLeft, CGFloat maxyRight)
{
    CGContextMoveToPoint(context, NSMinX(rect), NSMinY(rect) + minyLeft);
    CGContextAddLineToPoint(context, NSMinX(rect), NSMaxY(rect) - maxyLeft);
    CGContextAddArcToPoint(context, NSMinX(rect), NSMaxY(rect), NSMinX(rect) + maxyLeft, NSMaxY(rect), maxyLeft);
    CGContextAddLineToPoint(context, NSMaxX(rect) - maxyRight, NSMaxY(rect));
    CGContextAddArcToPoint(context, NSMaxX(rect), NSMaxY(rect), NSMaxX(rect), NSMaxY(rect) - maxyRight, maxyRight);
    CGContextAddLineToPoint(context, NSMaxX(rect), NSMinY(rect) + minyRight);
    CGContextAddArcToPoint(context, NSMaxX(rect), NSMinY(rect), NSMaxX(rect) - minyRight, NSMinY(rect), minyRight);
    CGContextAddLineToPoint(context, NSMinX(rect) + minyLeft, NSMinY(rect));
    CGContextAddArcToPoint(context, NSMinX(rect), NSMinY(rect), NSMinX(rect), NSMinY(rect) + minyLeft, minyLeft);
    CGContextClosePath(context);
}

@implementation OABezierPathIntersection
@synthesize left = _left;
@synthesize right = _right;
@synthesize location = _location;
@end
