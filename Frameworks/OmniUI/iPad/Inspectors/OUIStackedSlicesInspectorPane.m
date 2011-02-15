// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorBackgroundView.h>

RCS_ID("$Id$");

@interface OUIStackedSlicesInspectorPaneContentView : OUIInspectorBackgroundView
{
@private
    NSArray *_slices;
}
@property(nonatomic,copy) NSArray *slices;
@property(nonatomic,readonly) CGFloat contentHeightForViewInPopover;
@end

@implementation OUIStackedSlicesInspectorPaneContentView

- (void)dealloc;
{
    [_slices release];
    [super dealloc];
}

@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices;
{
    if (OFISEQUAL(_slices, slices))
        return;
    
    [_slices release];
    _slices = [slices copy];
    
    [self setNeedsLayout];
}

- (CGFloat)contentHeightForViewInPopover;
{
    if ([_slices count] == 0) {
        OBASSERT_NOT_REACHED("You probably want some slices.");
        return 0;
    }
    
    // Must mirror -layoutSubviews;
    CGFloat totalHeight = [[_slices objectAtIndex:0] paddingToInspectorTop];
    
    OUIInspectorSlice *previousSlice = nil;
    for (OUIInspectorSlice *slice in _slices) {
        // Don't fiddle with slices that have been stolen by embedding inspectors (OmniGraffle).
        UIView *sliceView = slice.view;
        if (sliceView.superview != self)
            continue;
        
        if (previousSlice)
            totalHeight += [slice paddingToPreviousSlice:previousSlice];
        
        totalHeight += CGRectGetHeight(sliceView.frame);
        previousSlice = slice;
    }
    
    totalHeight += [[_slices lastObject] paddingToInspectorBottom];

    return totalHeight;
}

- (void)layoutSubviews;
{
    // OUIInspectorBackgroundView adjusts its gradient here.
    [super layoutSubviews];
    
    if ([_slices count] == 0) {
        OBASSERT_NOT_REACHED("You probably want some slices.");
        return;
    }
    
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat yOffset = CGRectGetMinY(bounds);
        
    // Spacing between the header of the popover and the first slice (our slice nibs have their content jammed to the top, typically).
    yOffset += [[_slices objectAtIndex:0] paddingToInspectorTop];
    
    OUIInspectorSlice *previousSlice = nil;
    for (OUIInspectorSlice *slice in _slices) {
        // Don't fiddle with slices that have been stolen by embedding inspectors (OmniGraffle).
        UIView *sliceView = slice.view;
        if (sliceView.superview != self)
            continue;
        
        if (previousSlice)
            yOffset += [slice paddingToPreviousSlice:previousSlice];
        
        CGFloat sideInset = [slice paddingToInspectorSides];
        CGFloat sliceHeight = CGRectGetHeight(sliceView.frame);
        sliceView.frame = CGRectMake(CGRectGetMinX(bounds) + sideInset, yOffset, width - 2*sideInset, sliceHeight);
        yOffset += sliceHeight;
        
        previousSlice = slice;
    }
    
    yOffset += [[_slices lastObject] paddingToInspectorBottom];
    
    if (CGRectGetHeight(bounds) >= yOffset) {
        // Have been resized by UIPopoverController yet
        for (OUIInspectorSlice *slice in _slices) {
            // Don't fiddle with slices that have been stolen by embedding inspectors (OmniGraffle).
            UIView *sliceView = slice.view;
            if (sliceView.superview != self)
                continue;
        }
    }
}

@end

@interface OUIStackedSlicesInspectorPane ()
@property(nonatomic,copy) NSArray *slices;
@end

@implementation OUIStackedSlicesInspectorPane

- (void)dealloc;
{
    [_availableSlices release];
    [_slices release];
    [super dealloc];
}

- (NSArray *)makeAvailableSlices;
{
    return nil; // For subclasses
}

@synthesize availableSlices = _availableSlices;

- (NSArray *)appropriateSlicesForInspectedObjects;
{
    NSArray *slices = [self.inspector slicesForStackedSlicesPane:self];
    if (slices)
        return slices;
    
    // TODO: Add support for this style of use in the superclass? There already is in the delegate-based path.
    if (!_availableSlices) {
        _availableSlices = [[self makeAvailableSlices] copy];
        OBASSERT([_availableSlices count] > 0); // Didn't get slices from the delegate or a subclass!
    }
    
    NSSet *inspectedObjects = self.inspectedObjects;
    OBASSERT([inspectedObjects count] > 0); // Should be inspecting *something* or no slices will love us.
    
    NSMutableArray *appropriateSlices = [NSMutableArray array];
    for (OUIInspectorSlice *slice in _availableSlices) {
        if ([slice isAppropriateForInspectedObjects:inspectedObjects])
            [appropriateSlices addObject:slice];
    }

    return appropriateSlices;
}

@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices;
{
    if (OFISEQUAL(_slices, slices))
        return;
    
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;

    NSSet *oldSlices = [NSSet setWithArray:_slices];
    NSSet *newSlices = [NSSet setWithArray:slices];
    
    // TODO: Might want an 'animate' variant later.
    for (OUIInspectorSlice *slice in _slices) {
        if ([newSlices member:slice] == nil) {
            [self removeChildViewController:slice animated:NO];
            if ([slice isViewLoaded] && slice.view.superview == view) {
                [slice.view removeFromSuperview]; // Only remove it if it is loaded and wasn't stolen by an embedding inspector (OmniGraffle).
            }
            slice.containingPane = nil;
        }
    }

    [_slices release];
    _slices = [[NSArray alloc] initWithArray:slices];

    for (OUIInspectorSlice *slice in _slices) {
        if ([oldSlices member:slice] == nil) {
            slice.containingPane = self;
            
            // Add this once up front, but only if an embedding inspector hasn't stolen it from us (OmniGraffle). Not pretty, but that's how it is right now.
            if (slice.view.superview == nil)
                [view addSubview:slice.view];
            
            [self addChildViewController:slice animated:NO];
        }
    }
    
    view.slices = slices;
    
    [self inspectorSizeChanged];
    [self updateInspectorToolbarItems:NO/*animated*/];
}

- (void)inspectorSizeChanged;
{
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;
    self.contentSizeForViewInPopover = CGSizeMake(view.bounds.size.width, view.contentHeightForViewInPopover);
}

- (void)updateInspectorToolbarItems:(BOOL)animated;
{
    // Likely only slice (at most) will have toolbar items, but we don't have a good way to pick, so gather them all.
    NSMutableArray *toolbarItems = nil;
    
    for (OUIInspectorSlice *slice in _slices) {
        NSArray *sliceToolbarItems = slice.toolbarItems;
        if ([sliceToolbarItems count] > 0) {
            if (!toolbarItems)
                toolbarItems = [NSMutableArray array];
            [toolbarItems addObjectsFromArray:sliceToolbarItems];
        }
        
    }

    if (![toolbarItems isEqualToArray:self.toolbarItems])
        [self setToolbarItems:toolbarItems animated:animated];
    
    [super updateInspectorToolbarItems:animated];
}

#pragma mark -
#pragma mark OUIInspectorPane subclass

- (void)updateInterfaceFromInspectedObjects;
{
    [super updateInterfaceFromInspectedObjects];
    
    self.slices = [self appropriateSlicesForInspectedObjects];
    OBASSERT([_slices count] > 0); // If there really would be no applicable slices, the control to get here should have been disabled!
    
    [_slices makeObjectsPerformSelector:_cmd];
}

#pragma mark -
#pragma mark UIViewController

- (void)loadView;
{
    OUIStackedSlicesInspectorPaneContentView *view = [[OUIStackedSlicesInspectorPaneContentView alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 16)];
    self.view = view;
    [view release];
}

@end
