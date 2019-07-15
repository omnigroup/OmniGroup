// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSBezierPath.h>
#import <ApplicationServices/ApplicationServices.h> // CGContextRef
#import <OmniFoundation/OFGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSCountedSet, NSDictionary, NSMutableDictionary;

void OACGAddRoundedRect(CGContextRef context, NSRect rect, CGFloat topLeft, CGFloat topRight, CGFloat bottomLeft, CGFloat bottomRight);

enum OAIntersectionAspect {
    intersectionEntryLeft = -1,  // Other path crosses from left to right
    intersectionEntryAt = 0,     // Collinear or osculating
    intersectionEntryRight = 1,  // Other path crosses from right to left
    
    intersectionEntryBogus = -2, // Garbage value for unit testing
};

typedef NSInteger NSBezierPathSegmentIndex;  // It would make more sense for this to be unsigned, but NSBezierPath uses int, and so we follow its lead

typedef struct OABezierPathPosition {
    NSBezierPathSegmentIndex segment;
    double parameter;
} OABezierPathPosition;

typedef struct {
    NSBezierPathSegmentIndex segment;
    double parameter;
    double parameterDistance;
    // Unlike the lower-level calls, these aspects are ordered according to their occurrence on this path, not the other path. So 'firstAspect' is the aspect of the other line where it crosses us at (parameter), and 'secondAspect' is the aspect at (parameter.parameterDistance).
    enum OAIntersectionAspect firstAspect, secondAspect;
} OABezierPathIntersectionHalf;

@interface OABezierPathIntersection : NSObject

@property (nonatomic, readwrite) OABezierPathIntersectionHalf left;
@property (nonatomic, readwrite) OABezierPathIntersectionHalf right;
@property (nonatomic, readwrite) NSPoint location;

@end

// Utility functions used internally, may be of use to other callers as well
void OASplitBezierCurveTo(const NSPoint *c, CGFloat t, NSPoint *l, NSPoint *r);
BOOL OATightBoundsOfCurveTo(NSRect *r, NSPoint startPoint, NSPoint control1, NSPoint control2, NSPoint endPoint, CGFloat sideClearance);
extern void _OAParameterizeCurve(NSPoint *coefficients, NSPoint startPoint, NSPoint endPoint, NSPoint controlPoint1, NSPoint controlPoint2);

@interface NSBezierPath (OAExtensions)

+ (instancetype)bezierPathWithRoundedRectangle:(NSRect)rect byRoundingCorners:(OFRectCorner)corners withRadius:(CGFloat)radius;
+ (instancetype)bezierPathWithRoundedRectangle:(NSRect)rect byRoundingCorners:(OFRectCorner)corners withRadius:(CGFloat)radius includingEdges:(OFRectEdge)edges;

- (NSPoint)currentpointForSegment:(NSInteger)i;  // Raises an exception if no currentpoint

- (BOOL)strokesSimilarlyIgnoringEndcapsToPath:(NSBezierPath *)otherPath;
- (NSCountedSet *)countedSetOfEncodedStrokeSegments;

- (NSArray *)divideMultiplePaths;

- (BOOL)intersectsRect:(NSRect)rect;

// Returns the "start"-most intersection with the given line (that is, the intersection closest to the start of the line).
- (BOOL)intersectionWithLine:(NSPoint *)result lineStart:(NSPoint)lineStart lineEnd:(NSPoint)lineEnd;

// Returns the first intersection with the given line (that is, the intersection closest to the start of the receiver's bezier path).
- (BOOL)firstIntersectionWithLine:(OABezierPathIntersection * __nullable)result lineStart:(NSPoint)lineStart lineEnd:(NSPoint)lineEnd;

// Returns all the intersections between the receiver and the specified path. As a special case, if other==self, it does the useful thing and returns only the nontrivial self-intersections.
- (NSArray <OABezierPathIntersection *> *)allIntersectionsWithPath:(NSBezierPath *)other;

- (NSInteger)segmentHitByPoint:(NSPoint)point padding:(CGFloat)padding;
- (NSInteger)segmentHitByPoint:(NSPoint)point;  // 0 == no hit, padding == 5
- (BOOL)isStrokeHitByPoint:(NSPoint)point padding:(CGFloat)padding;
- (BOOL)isStrokeHitByPoint:(NSPoint)point; // padding == 5
- (NSInteger)segmentHitByPoint:(NSPoint)point position:(CGFloat *)position padding:(CGFloat)padding;

- (void)appendBezierPathWithRoundedRectangle:(NSRect)rect withRadius:(CGFloat)radius;
- (void)appendBezierPathWithLeftRoundedRectangle:(NSRect)rect withRadius:(CGFloat)radius;
- (void)appendBezierPathWithRightRoundedRectangle:(NSRect)rect withRadius:(CGFloat)radius;

- (void)appendBezierPathWithRoundedRectangle:(NSRect)rect byRoundingCorners:(OFRectCorner)corners withRadius:(CGFloat)radius includingEdges:(OFRectEdge)edges;

- (void)applyTransform:(CGAffineTransform)transform;

// The "position" manipulated by these methods divides the range 0..1 equally into segments corresponding to the Bezier's segments, and position within each segment is proportional to the t-parameter (not proportional to linear distance).
- (NSPoint)getPointForPosition:(CGFloat)position andOffset:(CGFloat)offset;
- (CGFloat)getPositionForPoint:(NSPoint)point;
- (CGFloat)getNormalForPosition:(CGFloat)position;

// "Length" is the actual length along the curve
- (double)lengthToSegment:(NSInteger)seg parameter:(double)parameter totalLength:(double * __nullable)totalLengthOut;

// Returns the segment and parameter corresponding to the point a certain distance along the curve. 'outParameter' may be NULL, which can save a small amount of computation if the parameter isn't needed.
- (NSInteger)segmentAndParameter:(double * __nullable)outParameter afterLength:(double)lengthFromStart fractional:(BOOL)lengthIsFractionOfTotal;

// Returns the location of a point specifed as a (segment,parameter) pair.
- (NSPoint)getPointForPosition:(OABezierPathPosition)pos;

- (BOOL)isClockwise;

// load and save
- (NSMutableDictionary *)propertyListRepresentation;
- (void)loadPropertyListRepresentation:(NSDictionary *)dict;

// NSObject overrides
- (BOOL)isEqual:(NSBezierPath * __nullable)otherBezierPath;
- (NSUInteger)hash;

@end

NS_ASSUME_NONNULL_END
