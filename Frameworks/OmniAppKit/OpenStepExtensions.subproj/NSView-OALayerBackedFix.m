// Copyright 2000-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSView-OALayerBackedFix.h>
#import <QuartzCore/CATransaction.h>

RCS_ID("$Id$");

@implementation NSView (OALayerBackedFix)

#ifdef OMNI_ASSERTIONS_ON

static void (*original_addSubview_positioned_relativeTo)(id self, SEL _cmd, NSView *aView, NSWindowOrderingMode place, NSView *otherView);

static Class _NSTileContainerLayerClass;
static NSString *const AddedSubviewsKey = @"com.omnigroup.OmniAppKit.OALayerBackedFix.AddedSubviews";

OBPerformPosing(^{
    _NSTileContainerLayerClass = NSClassFromString(@"_NSTileContainerLayer");
    if (_NSTileContainerLayerClass) {
        Class self = objc_getClass("NSView");
        original_addSubview_positioned_relativeTo = (typeof(original_addSubview_positioned_relativeTo))OBReplaceMethodImplementationWithSelector(self, @selector(addSubview:positioned:relativeTo:), @selector(OALayerBackedFix_addSubview:positioned:relativeTo:));
    } else {
        BOOL isOperatingSystemMavericksOrLater = YES; // [OFVersionNumber isOperatingSystemMavericksOrLater]
        if (!isOperatingSystemMavericksOrLater) {
            OBASSERT_NOT_REACHED("Cannot find class _NSTileContainerLayer; unable to warn about <bug:///86517> (13415520: -[NSView addSubview:positioned:relativeTo:] inserts sublayers in wrong position)");
        }
    }
});

- (void)OALayerBackedFix_addSubview:(NSView *)aView positioned:(NSWindowOrderingMode)place relativeTo:(NSView *)otherView;
{
    original_addSubview_positioned_relativeTo(self, _cmd, aView, place, otherView);
    
    NSMutableArray *addedSubviews = objc_getAssociatedObject(self, AddedSubviewsKey);
    if (!addedSubviews) {
        addedSubviews = [[NSMutableArray alloc] init];
        objc_setAssociatedObject(self, AddedSubviewsKey, addedSubviews, OBJC_ASSOCIATION_RETAIN);
        [addedSubviews release];
    }
    
    [addedSubviews addObject:aView];
    
    [self performSelector:@selector(OALayerBackedFix_verifySubviewLayerOrdering:) withObject:nil afterDelay:0];
}

- (void)OALayerBackedFix_verifySubviewLayerOrdering:(void *)passSelfIfTriedFix;
{
    CALayer *ourLayer = [self layer];
    NSArray *addedSubviews = [objc_getAssociatedObject(self, AddedSubviewsKey) retain];
    objc_setAssociatedObject(self, AddedSubviewsKey, nil, OBJC_ASSOCIATION_RETAIN);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(OALayerBackedFix_verifySubviewLayerOrdering:) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(OALayerBackedFix_verifySubviewLayerOrdering:) object:self];
    
    if (!ourLayer || [addedSubviews count] == 0) {
        [addedSubviews release];
        return;
    }
    
    for (NSView *aView in addedSubviews) {
        
        if ([aView superview] != self)
            continue;
        
        CALayer *subviewLayer = [aView layer];
        NSArray *ourSublayers = ourLayer.sublayers;
        
        CALayer *tilingLayer = nil;
        if (subviewLayer) {
            
            if (![ourSublayers containsObject:subviewLayer]) {
                OBASSERT_NOT_REACHED("Could not find layer for newly-added subview %@", [aView shortDescription]);
                return;
            }
            
            for (CALayer *sublayer in ourSublayers) {
                if ([sublayer isKindOfClass:_NSTileContainerLayerClass]) {
                    OBASSERT_NULL(tilingLayer, "Multiple sublayers of class _NSTileContainerLayer found; potential false positive or negative warning about bad layer ordering.")
                    
                    tilingLayer = sublayer;
                    break;
                }
            }
            
            if (tilingLayer && ([ourSublayers indexOfObject:subviewLayer] < [ourSublayers indexOfObject:tilingLayer])) {
                if (passSelfIfTriedFix) {
                    OBASSERT_NOT_REACHED("<bug:///86517> (13415520: -[NSView addSubview:positioned:relativeTo:] inserts sublayers in wrong position): -[NSView(OALayerBackedFix) fixSubviewLayerOrdering] failed to position layer '%@' for subview '%@' below automatic tiling layer '%@' for superview '%@'", [subviewLayer shortDescription], [aView shortDescription], [tilingLayer shortDescription], [self shortDescription]);
                } else {
                    OBASSERT_NOT_REACHED(@"*** <bug:///86517> (13415520: -[NSView addSubview:positioned:relativeTo:] inserts sublayers in wrong position): Layer '%@' for subview '%@' found ordered below automatic tiling layer '%@' for superview '%@'. To fix, send -fixSubviewLayerOrdering to superview.", [subviewLayer shortDescription], [aView shortDescription], [tilingLayer shortDescription], [self shortDescription]);
                }
            }
        }
    }
    
    [addedSubviews release];
}

#endif

static NSComparisonResult FixSortingComparator(id view1, id view2, void *context)
{
    NSArray *subviews = (NSArray *)context;
    NSUInteger idx1 = [subviews indexOfObject:view1], idx2 = [subviews indexOfObject:view2];
    
    if (idx1 < idx2)
        return NSOrderedAscending;
    else if (idx1 > idx2)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}


- (void)fixSubviewLayerOrdering;
{
    NSArray *subviews = [[self subviews] copy];
    [self sortSubviewsUsingFunction:FixSortingComparator context:subviews];
    [subviews release];
    
#ifdef OMNI_ASSERTIONS_ON
    [self OALayerBackedFix_verifySubviewLayerOrdering:self];
#endif
}

@end
