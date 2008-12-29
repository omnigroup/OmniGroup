// Copyright 2000-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSBezierPath-OAExtensions.h 104581 2008-09-06 21:18:23Z kc $

#import <AppKit/NSBezierPath.h>
#import <ApplicationServices/ApplicationServices.h> // CGContextRef

@class NSCountedSet, NSDictionary, NSMutableDictionary;

void OACGAddRoundedRect(CGContextRef context, NSRect rect, float topLeft, float topRight, float bottomLeft, float bottomRight);

enum OAIntersectionAspect {
    intersectionEntryLeft = -1,  // Other path crosses from left to right
    intersectionEntryAt = 0,     // Collinear or osculating
    intersectionEntryRight = 1,  // Other path crosses from right to left
    
    intersectionEntryBogus = -2, // Garbage value for unit testing
};

typedef int NSBezierPathSegmentIndex;  // It would make more sense for this to be unsigned, but NSBezierPath uses int, and so we follow its lead

typedef struct OABezierPathPosition {
    NSBezierPathSegmentIndex segment;
    double parameter;
} OABezierPathPosition;

typedef struct {
    struct OABezierPathIntersectionHalf {
        NSBezierPathSegmentIndex segment;
        double parameter;
        double parameterDistance;
        // Unlike the lower-level calls, these aspects are ordered according to their occurrence on this path, not the other path. So 'firstAspect' is the aspect of the other line where it crosses us at (parameter), and 'secondAspect' is the aspect at (parameter.parameterDistance).
        enum OAIntersectionAspect firstAspect, secondAspect;
    } left, right;
    NSPoint location;
} OABezierPathIntersection;

struct OABezierPathIntersectionList {
    unsigned count;
    OABezierPathIntersection *intersections;
};

// Utility functions used internally, may be of use to other callers as well
void splitBezierCurveTo(const NSPoint *c, float t, NSPoint *l, NSPoint *r);
BOOL tightBoundsOfCurveTo(NSRect *r, NSPoint startPoint, NSPoint control1, NSPoint control2, NSPoint endPoint, CGFloat sideClearance);

@interface NSBezierPath (OAExtensions)

- (NSPoint)currentpointForSegment:(int)i;  // Raises an exception if no currentpoint

- (BOOL)strokesSimilarlyIgnoringEndcapsToPath:(NSBezierPath *)otherPath;
- (NSCountedSet *)countedSetOfEncodedStrokeSegments;

- (BOOL)intersectsRect:(NSRect)rect;
- (BOOL)intersectionWithLine:(NSPoint *)result lineStart:(NSPoint)lineStart lineEnd:(NSPoint)lineEnd;

// Returns the first intersection with the given line (that is, the intersection closest to the start of the receiver's bezier path).
- (BOOL)firstIntersectionWithLine:(OABezierPathIntersection *)result lineStart:(NSPoint)lineStart lineEnd:(NSPoint)lineEnd;

// Returns a list of all the intersections between the receiver and the specified path. As a special case, if other==self, it does the useful thing and returns only the nontrivial self-intersections.
- (struct OABezierPathIntersectionList)allIntersectionsWithPath:(NSBezierPath *)other;

- (void)getWinding:(int *)clockwiseWindingCount andHit:(unsigned int *)strokeHitCount forPoint:(NSPoint)point;

- (int)segmentHitByPoint:(NSPoint)point padding:(float)padding;
- (int)segmentHitByPoint:(NSPoint)point;  // 0 == no hit, padding == 5
- (BOOL)isStrokeHitByPoint:(NSPoint)point padding:(float)padding;
- (BOOL)isStrokeHitByPoint:(NSPoint)point; // padding == 5

//
- (void)appendBezierPathWithRoundedRectangle:(NSRect)aRect withRadius:(float)radius;
- (void)appendBezierPathWithLeftRoundedRectangle:(NSRect)aRect withRadius:(float)radius;
- (void)appendBezierPathWithRightRoundedRectangle:(NSRect)aRect withRadius:(float)radius;

// The "position" manipulated by these methods divides the range 0..1 equally into segments corresponding to the Bezier's segments, and position within each segment is proportional to the t-parameter (not proportional to linear distance).
- (NSPoint)getPointForPosition:(float)position andOffset:(float)offset;
- (float)getPositionForPoint:(NSPoint)point;
- (float)getNormalForPosition:(float)position;

// "Length" is the actual length along the curve
- (double)lengthToSegment:(int)seg parameter:(double)parameter totalLength:(double *)totalLengthOut;

// Returns the segment and parameter corresponding to the point a certain distance along the curve. 'outParameter' may be NULL, which can save a small amount of computation if the parameter isn't needed.
- (int)segmentAndParameter:(double *)outParameter afterLength:(double)lengthFromStart fractional:(BOOL)lengthIsFractionOfTotal;

// Returns the location of a point specifed as a (segment,parameter) pair.
- (NSPoint)getPointForPosition:(OABezierPathPosition)pos;

- (BOOL)isClockwise;

// load and save
- (NSMutableDictionary *)propertyListRepresentation;
- (void)loadPropertyListRepresentation:(NSDictionary *)dict;

// NSObject overrides
- (BOOL)isEqual:(NSBezierPath *)otherBezierPath;
- (unsigned int)hash;

@end
