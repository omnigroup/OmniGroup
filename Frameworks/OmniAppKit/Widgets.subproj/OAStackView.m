// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAStackView.h>

#import <AppKit/NSWindow.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSInvocation.h>
#import <OmniBase/OmniBase.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>
#import <OmniAppKit/NSAnimationContext-OAExtensions.h>

RCS_ID("$Id$")


NSString * const OAStackViewDidLayoutSubviews = @"OAStackViewDidLayoutSubviews";

static unsigned OASVHiddenSubviewContext;
static NSString * const OASVHiddenSubviewProperty = @"hidden";

@interface OAStackView ()
{
    NSMutableArray *_availableSubviews;
}

@end

/*"
OAStackView assumes that all of its subviews line up in one direction (only vertical stacks are supported currently).  When a view is removed, the space is taken up by other views (currently the last view takes all the extra space) and the gap is removed by sliding adjacent views into that space.
"*/
@implementation OAStackView

- (void)dealloc;
{
    for (NSView *view in _availableSubviews)
        [view removeObserver:self forKeyPath:OASVHiddenSubviewProperty context:&OASVHiddenSubviewContext];
    [_availableSubviews release];
    [super dealloc];
}

//
// API
//

- (id) dataSource;
{
    return dataSource;
}

- (void) setDataSource: (id) aDataSource;
{
    dataSource = aDataSource;
    flags.needsReload = YES;

    // This is really a bug.  If we don't do this (not sure if the layout is necessary, but the reload is), then the first window in OmniWeb will not show up (it gets an exception down in the drawing code).  While it seems permissible to ask the data source as soon as we have one, the data source might have some setup of its own left to do.  This way, we force it to be valid immediately which could be bad, but not much we can do with NSView putting the smack down on us.
    // This is bad because if we're unarchiving self and dataSource and establishing the datasource connection from a nib, it imposes nib ordering requirements.  The datasource may not have its outlets hooked up that it needs for subviewsForStackView:, for example.  <bug://bugs/53121> (-[OAStackView setDataSource:] implementation imposes nib ordering requirements)
    [self _loadSubviews];
    [self _layoutSubviews];

    if (dataSource != nil && dataSource != self && _availableSubviews.count != 0)
        [NSException raise:NSInternalInconsistencyException format:@"Do not add views directly to a OAStackView -- use the dataSource"];

}

- (void) reloadSubviews;
{
    [self _loadSubviews];
    [self _layoutSubviews];
    [self setNeedsDisplay: YES];
}

- (void) subviewSizeChanged;
{
    //NSLog(@"subviewSizeChanged");
    [self _queueLayout];
}

- (void)setLayoutEnabled:(BOOL)layoutEnabled display:(BOOL)display;
{
    flags.layoutDisabled = !layoutEnabled;
    if (display)
        [self setNeedsDisplay:YES];
}

//
// NSView subclass
//

- (BOOL)isFlipped;
{
    return YES;
}

- (void) addSubview: (NSView *) view;
{
    if (dataSource != nil && dataSource != self) {
        // This doesn't protect against having a subview removed, but some checking is better than none.
        [NSException raise:NSInternalInconsistencyException format:@"Do not add views directly to a OAStackView -- use the dataSource"];
    }

    [super addSubview:view];

    if (OFISEQUAL(NSStringFromClass([view class]), @"NSCustomView")) {
        // Ignore this cruft from a xib
        return;
    }

    if (_availableSubviews == nil)
        _availableSubviews = [[NSMutableArray alloc] init];

    [_availableSubviews insertObject:view inArraySortedUsingComparator:^NSComparisonResult(NSView *view1, NSView *view2) {
        CGFloat y1 = view1.frame.origin.y;
        CGFloat y2 = view2.frame.origin.y;
        if (y1 > y2)
            return NSOrderedAscending;
        else if (y1 < y2)
            return NSOrderedDescending;
        else
            return NSOrderedSame;
    }];

    [view addObserver:self forKeyPath:OASVHiddenSubviewProperty options:NSKeyValueObservingOptionNew context:&OASVHiddenSubviewContext];

    [self _setNeedsReload];
}

#pragma mark - OAStackView private API

static NSComparisonResult compareBasedOnArray(id object1, id object2, void *orderedObjects)
{
    NSUInteger index1 = [(NSArray *)orderedObjects indexOfObjectIdenticalTo:object1];
    NSUInteger index2 = [(NSArray *)orderedObjects indexOfObjectIdenticalTo:object2];
    if (index1 == index2)
        return NSOrderedSame;
    else if (index1 < index2)
        return NSOrderedAscending;
    else
        return NSOrderedDescending;
}

- (NSArray *)_visibleAvailableSubviews;
{
    return [_availableSubviews select:^BOOL(NSView *view) { return ![view isHidden]; }];
}

- (void)_loadSubviews;
{
    nonretained_stretchyView = nil;
    flags.needsReload = NO;
    flags.needsLayout = YES;
    
    OAWithoutAnimation(^{
        NSArray *subviews = [dataSource subviewsForStackView: self];
        if (subviews == nil) {
            subviews = [self _visibleAvailableSubviews];
        }
        
        // Remove any current subviews that aren't in the new list.  We assume that the number of views is small so an O(N*M) loop is OK
        {
            NSArray *currentSubviews = [self subviews];
            NSUInteger subviewIndex = [currentSubviews count];
            while (subviewIndex--) {
                NSView *oldSubview;
                
                oldSubview = [currentSubviews objectAtIndex: subviewIndex];
                if ([subviews indexOfObjectIdenticalTo: oldSubview] == NSNotFound)
                    [oldSubview removeFromSuperview];
            }
        }

        // Find the (currently first) view that is going to stretch vertically.
        // Set the autosizing flags such that we will layout correctly due to normal NSView resizing logic (once we have layed out once correctly).
        NSUInteger subviewCount = [subviews count];
        for (NSUInteger subviewIndex = 0; subviewIndex < subviewCount; subviewIndex++) {
            // Get the view and set the autosizing flags correctly.  This will mean that the layout will be correct when we get resized due to the normal NSView resizing logic
            NSView *view = [subviews objectAtIndex: subviewIndex];
            NSUInteger mask = [view autoresizingMask];
            if (mask & NSViewHeightSizable && !nonretained_stretchyView) {
                nonretained_stretchyView = view;
                [view setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
            } else {
                if (nonretained_stretchyView)
                    // this view comes after (below) the stretchy view
                    [view setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
                else
                    // this view comes before (above) the stretchy view
                    [view setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
            }
            
            // Call super to work around the -addSubview: check above.  Only add the view if it isn't already one of our subviews
            if ([view superview] != self)
                [super addSubview: view];
        }
        [self sortSubviewsUsingFunction:compareBasedOnArray context:subviews];
    });
}

/*"
Goes through the subviews and finds the first subview that is willing to stretch vertically.  This view is then given all of the height that is not taken by the other subviews.
"*/
- (void)_layoutSubviews;
{
    if (flags.layoutDisabled)
        return;
        
    if (flags.needsReload)
        [self _loadSubviews];

    flags.needsLayout = NO;

    OAWithoutAnimation(^{
        NSRect subviewFrame;
        NSRect spaceLeft = [self bounds];
        //NSLog(@"total bounds = %@", NSStringFromRect(spaceLeft));

        NSArray *currentSubviews = [self subviews];

        NSUInteger viewCount = [currentSubviews count];
        
        // Figure out how much space will be taken by the non-stretchy views
        CGFloat stretchyHeight = spaceLeft.size.height;
        for (NSUInteger viewIndex = 0; viewIndex < viewCount; viewIndex++) {
            NSView *view = [currentSubviews objectAtIndex: viewIndex];
            if (view != nonretained_stretchyView) {
                subviewFrame = [view frame];
                stretchyHeight -= subviewFrame.size.height;
            }
        }
        
        //NSLog(@"stretchyHeight = %f", stretchyHeight);
        
        if (nonretained_stretchyView && stretchyHeight < 0.0f)
            stretchyHeight = 0.0f;
        
        if (nonretained_stretchyView == nil) {
            NSRect newFrame = self.frame;
            newFrame.size.height -= stretchyHeight;
            self.frame = newFrame;
            spaceLeft = self.bounds;
            stretchyHeight = 0.0f;
        }

        // Now set the frame of each of the rectangles
        NSUInteger viewIndex = viewCount;
        while (viewIndex--) {
            CGFloat viewHeight;
            
            NSView *view = [currentSubviews objectAtIndex: viewIndex];
            
            if (view == nonretained_stretchyView)
                viewHeight = stretchyHeight;
            else {
                subviewFrame = [view frame];
                viewHeight = NSHeight(subviewFrame);
            }

            subviewFrame = NSMakeRect(NSMinX(spaceLeft), NSMaxY(spaceLeft) - viewHeight,
                                    NSWidth(spaceLeft), viewHeight);
            [view setFrame: subviewFrame];
            //NSLog(@"  subview %@  new frame = %@", [view shortDescription], NSStringFromRect(subviewFrame));
    
            spaceLeft.size.height -= subviewFrame.size.height;
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:OAStackViewDidLayoutSubviews object:self];
    });
}

- (void)layout;
{
    [super layout];
    [self _layoutSubviews];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize;
{
    [self layout];
}

#pragma mark - NSObject (NSKeyValueObserving)

- (void)_queueLayout;
{
    flags.needsLayout = YES;

    [NSWindow beforeAnyDisplayIfNeededPerformBlock:^{
        if (self.window != nil) {
            [self _layoutSubviews];
        }
    }];
}

- (void)_setNeedsReload;
{
    if (flags.needsReload)
        return;

    flags.needsReload = YES;
    [self _queueLayout];
    [self setNeedsDisplay:YES];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &OASVHiddenSubviewContext) {
        [self _setNeedsReload];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


@end

@implementation NSView (OAStackViewHelper)

- (OAStackView *) enclosingStackView;
{
    NSView *view;
    Class stackViewClass;
    
    view = [self superview];
    stackViewClass = [OAStackView class];
    
    while (view && ![view isKindOfClass: stackViewClass])
        view = [view superview];
        
    return (OAStackView *)view;
}

@end

