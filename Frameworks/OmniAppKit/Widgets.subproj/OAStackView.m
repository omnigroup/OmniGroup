// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
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

RCS_ID("$Id$")


NSString * const OAStackViewDidLayoutSubviews = @"OAStackViewDidLayoutSubviews";


@interface OAStackView (PrivateAPI)
- (void) _loadSubviews;
- (void) _layoutSubviews;
@end

/*"
OAStackView assumes that all of its subviews line up in one direction (only vertical stacks are supported currently).  When a view is removed, the space is taken up by other views (currently the last view takes all the extra space) and the gap is removed by sliding adjacent views into that space.
"*/
@implementation OAStackView

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
    flags.needsReload = 1;

    // This is really a bug.  If we don't do this (not sure if the layout is necessary, but the reload is), then the first window in OmniWeb will not show up (it gets an exception down in the drawing code).  While it seems permissible to ask the data source as soon as we have one, the data source might have some setup of its own left to do.  This way, we force it to be valid immediately which could be bad, but not much we can do with NSView putting the smack down on us.
    // This is bad because if we're unarchiving self and dataSource and establishing the datasource connection from a nib, it imposes nib ordering requirements.  The datasource may not have its outlets hooked up that it needs for subviewsForStackView:, for example.  <bug://bugs/53121> (-[OAStackView setDataSource:] implementation imposes nib ordering requirements)
    [self _loadSubviews];
    [self _layoutSubviews];
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
    flags.needsLayout = 1;
    [self setNeedsDisplay: YES];
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

- (void) drawRect: (NSRect) rect;
{
    if (flags.needsReload)
        [self _loadSubviews];
    if (flags.needsLayout)
        [self _layoutSubviews];

    // This doesn't draw the subviews, we're just hooking the reset of the subviews here since this should get done before they are drawn.
    [super drawRect: rect];
}

// This doesn't protect against having a subview removed, but some checking is better than none.
- (void) addSubview: (NSView *) view;
{
    [NSException raise: NSInternalInconsistencyException
                format: @"Do not add views directly to a OAStackView -- use the dataSource"];
}

@end

@implementation OAStackView (PrivateAPI)

static NSInteger compareBasedOnArray(id object1, id object2, void *orderedObjects)
{
    int index1, index2;

    index1 = [(NSArray *)orderedObjects indexOfObjectIdenticalTo:object1];
    index2 = [(NSArray *)orderedObjects indexOfObjectIdenticalTo:object2];
    if (index1 == index2)
        return NSOrderedSame;
    else if (index1 < index2)
        return NSOrderedAscending;
    else
        return NSOrderedDescending;
}

- (void) _loadSubviews;
{
    NSArray *subviews;
    unsigned int subviewIndex, subviewCount;
    BOOL oldAutodisplay;
    
    
    nonretained_stretchyView = nil;
    flags.needsReload = 0;
    flags.needsLayout = 1;
    
    oldAutodisplay = [_window isAutodisplay];
    [_window setAutodisplay: NO];
    [_window disableFlushWindow];
    
    NS_DURING {
        subviews = [dataSource subviewsForStackView: self];
        
        // Remove any current subviews that aren't in the new list.  We assume that the number of views is small so an O(N*M) loop is OK
        {
            NSArray *currentSubviews = [self subviews];
            subviewIndex = [currentSubviews count];
            while (subviewIndex--) {
                NSView *oldSubview;
                
                oldSubview = [currentSubviews objectAtIndex: subviewIndex];
                if ([subviews indexOfObjectIdenticalTo: oldSubview] == NSNotFound)
                    [oldSubview removeFromSuperview];
            }
        }

        // Find the (currently first) view that is going to stretch vertically.
        // Set the autosizing flags such that we will layout correctly due to normal NSView resizing logic (once we have layed out once correctly).
        subviewCount = [subviews count];
        for (subviewIndex = 0; subviewIndex < subviewCount; subviewIndex++) {
            NSView *view;
            unsigned int mask;
            
            // Get the view and set the autosizing flags correctly.  This will mean that the layout will be correct when we get resized due to the normal NSView resizing logic
            view = [subviews objectAtIndex: subviewIndex];
            mask = [view autoresizingMask];
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
        
        if (!nonretained_stretchyView)
            NSLog(@"OAStackView: No vertically resizable subview returned from dataSource.");
    } NS_HANDLER {
        NSLog(@"Exception ignored during -[OAStackView _loadSubviews]: %@", localException);
    } NS_ENDHANDLER;
    
    [_window setAutodisplay: oldAutodisplay];
    if (oldAutodisplay)
        [_window setViewsNeedDisplay: YES];
    [_window enableFlushWindow];
}

/*"
Goes through the subviews and finds the first subview that is willing to stretch vertically.  This view is then given all of the height that is not taken by the other subviews.
"*/
- (void) _layoutSubviews;
{
    unsigned int viewIndex, viewCount;
    NSView *view;
    NSRect spaceLeft;
    NSRect subviewFrame;
    BOOL oldAutodisplay;
    float stretchyHeight;

    if (flags.layoutDisabled)
        return;
        
    flags.needsLayout = 0;

    spaceLeft = [self bounds];
    //NSLog(@"total bounds = %@", NSStringFromRect(spaceLeft));
    
    oldAutodisplay = [_window isAutodisplay];
    [_window setAutodisplay: NO];
    [_window disableFlushWindow];
    
    NS_DURING {
        NSArray *currentSubviews = [self subviews];

        viewCount = [currentSubviews count];
        
        // Figure out how much space will be taken by the non-stretchy views
        stretchyHeight = spaceLeft.size.height;
        for (viewIndex = 0; viewIndex < viewCount; viewIndex++) {
            view = [currentSubviews objectAtIndex: viewIndex];
            if (view != nonretained_stretchyView) {
                subviewFrame = [view frame];
                stretchyHeight -= subviewFrame.size.height;
            }
        }
        
        //NSLog(@"stretchyHeight = %f", stretchyHeight);
        
        if (stretchyHeight < 0.0)
            stretchyHeight = 0.0;
        
        // Now set the frame of each of the rectangles
        viewIndex = viewCount;
        while (viewIndex--) {
            float viewHeight;
            
            view = [currentSubviews objectAtIndex: viewIndex];
            
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
        
        [[NSNotificationCenter defaultCenter] postNotificationName: OAStackViewDidLayoutSubviews
                                                            object: self];
        
    } NS_HANDLER {
        NSLog(@"Exception ignored during -[OAStackView _layoutSubviews]: %@", localException);
    } NS_ENDHANDLER;
    
    [_window setAutodisplay: oldAutodisplay];
    if (oldAutodisplay)
        [_window setViewsNeedDisplay: YES];
    [_window enableFlushWindow];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize;
{
    [self _layoutSubviews];
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

