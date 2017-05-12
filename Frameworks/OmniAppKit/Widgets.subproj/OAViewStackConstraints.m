// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/AppKit.h>
#import <OmniAppKit/OAViewStackConstraints.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@implementation OAViewStackConstraints
{
    NSArray <NSView *> *views;
    NSLayoutAnchor *before, *after;
    NSMutableDictionary <NSString *, NSLayoutConstraint *> *cache;
    NSLayoutConstraintOrientation axis;
}

@synthesize views = views;
@synthesize emptySpacing, firstSpacing, spacing, lastSpacing;
@synthesize flipped;

- (instancetype)initWithViews:(NSArray <NSView *> *)views_ between:(NSLayoutAnchor *)before_ and:(NSLayoutAnchor *)after_ axis:(NSLayoutConstraintOrientation)axis_;
{
    if (!(self = [super init]))
        return nil;
    
    axis = axis_;
    views = [views_ copy];
    before = before_;
    after = after_;
    cache = [NSMutableDictionary dictionary];
    
    firstSpacing = -1;
    lastSpacing = -1;
    emptySpacing = -1;
    spacing = 8.0;
    
    flipped = ( axis_ == NSLayoutConstraintOrientationVertical )? YES : NO;
    
    return self;
}

- (NSLayoutConstraint *)_constraintFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex fallback:(BOOL)isFallbackConstraint outCacheKey:(NSString **)outKey;
{
    CGFloat thisSpacing;
    NSString * __autoreleasing constraintKey;
    
    if (fromIndex < 0) {
        if (toIndex < 0) {
            thisSpacing = emptySpacing;
            constraintKey = @":";
        } else {
            thisSpacing = firstSpacing;
            constraintKey = [NSString stringWithFormat:@":%" PRIdNS, toIndex];
        }
    } else {
        if (toIndex < 0) {
            thisSpacing = lastSpacing;
            constraintKey = [NSString stringWithFormat:@"%" PRIdNS ":", fromIndex];
        } else {
            thisSpacing = spacing;
            constraintKey = [NSString stringWithFormat:@"%" PRIdNS ":%" PRIdNS, fromIndex, toIndex];
        }
    }
    
    if (isFallbackConstraint)
        constraintKey = [@"F " stringByAppendingString:constraintKey];
    
    if (outKey)
        *outKey = constraintKey;
    
    NSLayoutConstraint *constraint = [cache objectForKey:constraintKey];
    if (constraint)
        return constraint;
    
    NSLayoutAnchor *fromAnchor, *toAnchor;
    if (axis == NSLayoutConstraintOrientationVertical) {
        fromAnchor = (fromIndex >= 0)? [views objectAtIndex:fromIndex].bottomAnchor : before;
        toAnchor = (toIndex >= 0)? [views objectAtIndex:toIndex].topAnchor : after;
    } else {
        fromAnchor = (fromIndex >= 0)? [views objectAtIndex:fromIndex].trailingAnchor : before;
        toAnchor = (toIndex >= 0)? [views objectAtIndex:toIndex].leadingAnchor : after;
    }
    
    if (thisSpacing < 0)
        thisSpacing = spacing;

    constraint = flipped? [toAnchor constraintEqualToAnchor:fromAnchor constant:thisSpacing] : [fromAnchor constraintEqualToAnchor:toAnchor constant:thisSpacing];
#if DEBUG
    constraint.identifier = constraintKey;
#endif
    [cache setObject:constraint forKey:constraintKey];
    constraint.priority = isFallbackConstraint? NSLayoutPriorityDefaultLow-1 : NSLayoutPriorityRequired;

    return constraint;
}

- (void)updateViewConstraints;
{
    NSMutableSet <NSString *> *oldConstraints = [NSMutableSet setByEnumerating:cache.keyEnumerator];
    NSMutableArray <NSLayoutConstraint *> *constraintsToActivate = [NSMutableArray array];
    
    /* Run through all the views we manage, getting the constraints that align each vew with the last. */
    NSInteger previousVisibleView = -1;
    NSUInteger viewCount = views.count;
    for(NSUInteger viewIndex = 0; viewIndex < viewCount; viewIndex ++) {
        
        BOOL thisViewIsHidden = [views objectAtIndex:viewIndex].hiddenOrHasHiddenAncestor;
        
        // To avoid ambiguous layout, we pin hidden views to the previous visible view even though they're hidden.
        NSString * __autoreleasing constraintKey;
        NSLayoutConstraint *constraint = [self _constraintFromIndex:previousVisibleView toIndex:viewIndex fallback:thisViewIsHidden outCacheKey:&constraintKey];
        [oldConstraints removeObject:constraintKey];
        if (!constraint.active)
            [constraintsToActivate addObject:constraint];

        if (thisViewIsHidden) {
            continue;
        } else {
            previousVisibleView = viewIndex;
        }
    }
    
    {
        NSString * __autoreleasing constraintKey;
        NSLayoutConstraint *constraint = [self _constraintFromIndex:previousVisibleView toIndex:-1 fallback:NO outCacheKey:&constraintKey];
        constraint.priority = NSLayoutPriorityRequired;
        [oldConstraints removeObject:constraintKey];
        if (!constraint.active)
            [constraintsToActivate addObject:constraint];
    }
    
    for (NSString *key in oldConstraints) {
        [cache objectForKey:key].active = NO; // -setActive: already tests for no-change and short circuits in that case, so no need for us to do that.
    }
    [NSLayoutConstraint activateConstraints:constraintsToActivate];
}

- (NSLayoutConstraint *)constraintFrom:(NSView *)from to:(NSView *)to;
{
    NSUInteger fromIndex = [views indexOfObjectIdenticalTo:from];
    if (fromIndex == NSNotFound)
        OBRejectInvalidCall(self, _cmd, @"Unknown view %@", [from shortDescription]);
    NSUInteger toIndex = [views indexOfObjectIdenticalTo:to];
    if (toIndex == NSNotFound)
        OBRejectInvalidCall(self, _cmd, @"Unknown view %@", [to shortDescription]);
    if (fromIndex >= toIndex)
        OBRejectInvalidCall(self, _cmd, @"Views are not in the right order");
    
    return [self _constraintFromIndex:fromIndex toIndex:toIndex fallback:NO outCacheKey:NULL];
}

- (NSArray <NSLayoutConstraint *> *)constraints;
{
    return [cache allValues];
}

@end
