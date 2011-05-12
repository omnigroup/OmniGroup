// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>

#import "OUIInspectorBackgroundView.h"

RCS_ID("$Id$");

@interface OUIStackedSlicesInspectorPaneContentView : UIScrollView
{
@private
    CGFloat _backgroundHeight;
    OUIInspectorBackgroundView *_backgroundView;
    NSArray *_slices;
}
@property(nonatomic,assign) CGFloat backgroundHeight;
@property(nonatomic,copy) NSArray *slices;
@end

@implementation OUIStackedSlicesInspectorPaneContentView

static id _commonInit(OUIStackedSlicesInspectorPaneContentView *self)
{
    self->_backgroundView = [[OUIInspectorBackgroundView alloc] initWithFrame:self.bounds];
    [self addSubview:self->_backgroundView];
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    [_backgroundView release];
    [_slices release];
    [super dealloc];
}

@synthesize backgroundHeight = _backgroundHeight;
@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices;
{
    if (OFISEQUAL(_slices, slices))
        return;
    
    [_slices release];
    _slices = [slices copy];
    
    [self setNeedsLayout];
}

- (void)layoutSubviews;
{
    [super layoutSubviews]; // Scroller

    NSUInteger sliceCount = [_slices count];
    if (sliceCount == 0) {
        // Should only get zero slices if the inspector is closed.
        OBASSERT(self.window == nil);
        return;
    }
    
    const CGRect bounds = self.bounds;
    const CGFloat width = CGRectGetWidth(bounds);
    
    CGFloat yOffset = 0;
    
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
        
        // If we have exactly one slice and it is marked height-sizable, give it our full bounds. This is useful for cases where we have a slice wrapper for something that normally wouldn't be a slice but is to make other things work more easily (like the columns tab of the contents inspector in OO/iPad). May revisit this later.
        CGFloat sliceHeight;
        if (sliceCount == 1 && (sliceView.autoresizingMask & UIViewAutoresizingFlexibleHeight)) {
            sliceHeight = bounds.size.height - ([slice paddingToInspectorTop] + [slice paddingToInspectorBottom]);
        } else {
            // Otherwise the slice should be a fixed height and we should use it.
            sliceHeight = CGRectGetHeight(sliceView.frame);
        }
        
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
    
    self.contentSize = CGSizeMake(bounds.size.width, yOffset);
    self.scrollEnabled = yOffset > bounds.size.height;

    // Have to do this after the previous adjustments or the background view can get stuck scrolled part way down when we become unscrollable.
    CGRect backgroundFrame = self.bounds;
    if (_backgroundHeight > 0)
        backgroundFrame.size.height = _backgroundHeight;
    
    _backgroundView.frame = backgroundFrame;
    
    // Terrible, but none of the other callbacks are timed so that the slices can alter the scroll position (since the content size isn't updated yet).
    for (OUIInspectorSlice *slice in _slices)
        [slice containingPaneDidLayout];
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
- (void)setAvailableSlices:(NSArray *)availableSlices;
{
    if (OFISEQUAL(_availableSlices, availableSlices))
        return;
    
    [_availableSlices release];
    _availableSlices = [availableSlices copy];
    
    if (self.visibility != OUIViewControllerVisibilityHidden) {
        // If we are currently on screen, a subclass might be changing the available slices somehow (like the tabbed document contents inspector in OO/iPad).
        // This will both update the filtered slices and their interface for the current inspection set.
        [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
    }
}

- (NSArray *)appropriateSlicesForInspectedObjects;
{
    // Only fill the _availableSlices once. This allows the delegate/subclass to return an autoreleased array that isn't stored in a static (meaning that they can go away on a low memory warning). If we fill this multiple times, then we'll get confused and replace the slices constantly (since we do pointer equality in -setSlices:.
    if (!_availableSlices) {
        _availableSlices = [[self.inspector makeAvailableSlicesForStackedSlicesPane:self] copy];
        if (_availableSlices)
            return _availableSlices;
    }
    
    // TODO: Add support for this style of use in the superclass? There already is in the delegate-based path.
    if (!_availableSlices) {
        _availableSlices = [[self makeAvailableSlices] copy];
        OBASSERT([_availableSlices count] > 0); // Didn't get slices from the delegate or a subclass!
    }

    // can be empty if the inspector is being closed
    NSArray *inspectedObjects = self.inspectedObjects;
    
    NSMutableArray *appropriateSlices = [NSMutableArray array];
    for (OUIInspectorSlice *slice in _availableSlices) {
        if ([slice isAppropriateForInspectedObjects:inspectedObjects])
            [appropriateSlices addObject:slice];
    }

    return appropriateSlices;
}

static void _removeSlice(OUIStackedSlicesInspectorPane *self, OUIStackedSlicesInspectorPaneContentView *view, OUIInspectorSlice *slice)
{
    [self removeChildViewController:slice animated:NO];
    if ([slice isViewLoaded] && slice.view.superview == view) {
        [slice.view removeFromSuperview]; // Only remove it if it is loaded and wasn't stolen by an embedding inspector (OmniGraffle).
    }
    slice.containingPane = nil;
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
            _removeSlice(self, view, slice);
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
}

- (void)sliceSizeChanged:(OUIInspectorSlice *)slice;
{
    [self.view setNeedsLayout];
}

#pragma mark -
#pragma mark OUIInspectorPane subclass

- (void)_updateSlices;
{
    self.slices = [self appropriateSlicesForInspectedObjects];
    
#ifdef OMNI_ASSERTIONS_ON
    if ([_slices count] == 0) {
        // Inspected objects is nil if the inspector gets closed. Othrwise, if there really would be no applicable slices, the control to get here should have been disabled!    
        OBASSERT(self.inspectedObjects == nil);
        OBASSERT(self.visibility == OUIViewControllerVisibilityHidden);
    }
#endif
}

- (void)inspectorWillShow:(OUIInspector *)inspector;
{
    [super inspectorWillShow:inspector];
    
    // Force the background to always be the same height. This avoids issues with it shrinking and being flickery when we gain/lose a bottom toolbar.
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;
    view.backgroundHeight = inspector.height;
    
    // This gets called earlier than -updateInterfaceFromInspectedObjects:. Might want to switch to just calling -updateInterfaceFromInspectedObjects: here instead of in -viewWillAppear:
    [self _updateSlices];
    
    for (OUIInspectorSlice *slice in _slices) {
        OMNI_POOL_START {
            [slice inspectorWillShow:inspector];
        } OMNI_POOL_END;
    }
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    [self _updateSlices];
    
    for (OUIInspectorSlice *slice in _slices) {
        OMNI_POOL_START {
            [slice updateInterfaceFromInspectedObjects:reason];
        } OMNI_POOL_END;
    }
}

#pragma mark -
#pragma mark UIViewController

- (void)didReceiveMemoryWarning;
{
    // Make sure to do this only when the whole inspector is hidden. We don't want to kill off a pane that pushed a detail pane.
    if (self.visibility == OUIViewControllerVisibilityHidden && ![self.inspector isVisible]) {
        // Remove our slices now to avoid getting assertion failures about their views not being subviews of ours when we remove them.
        
        // Ditch our current slices too. When we get reloaded, we'll rebuild and re add them.
        OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;
        for (OUIInspectorSlice *slice in _slices)
            _removeSlice(self, view, slice);
        
        [_slices release];
        _slices = nil;
        
        // Make sure this doesn't hold onto these for its next -layoutSubviews
        view.slices = nil;
        
        // Tell all our available slices about this tradegy now that they aren't children view controllers.
        [_availableSlices makeObjectsPerformSelector:@selector(fakeDidReceiveMemoryWarning)];
    }
    
    [super didReceiveMemoryWarning];
}

- (CGSize)contentSizeForViewInPopover;
{
    return [super contentSizeForViewInPopover];
}

- (void)loadView;
{
    OUIStackedSlicesInspectorPaneContentView *view = [[OUIStackedSlicesInspectorPaneContentView alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 16)];
    
    // If we are getting our view reloaded after a memory warning, we might already have slices. They should be mostly set up, but their superview needs fixing.
    for (OUIInspectorSlice *slice in _slices) {
        OBASSERT(slice.containingPane == self);
        OBASSERT([self isChildViewController:slice]);
        [view addSubview:slice.view];
    }
    view.slices = _slices;
    
    self.view = view;
    [view release];
}

- (void)viewDidUnload;
{
    OBPRECONDITION(self.visibility == OUIViewControllerVisibilityHidden);

    [super viewDidUnload];
    
    OBASSERT(self.inspector.visible || _slices == nil); // We expect -didReceiveMemoryWarning to do this, unless our inspector is still shown
}

- (void)viewWillAppear:(BOOL)animated;
{
    // Sadly, UINavigationController calls -navigationController:willShowViewController:animated: (which we use to provoke -inspectorWillShow:) BEFORE -viewWillAppear: when pushing but AFTER when popping. So, we have to update our list of child view controllers here too to avoid assertions in our life cycle checking. We don't want to send slices -viewWillAppear: and then drop them w/o ever sending -viewDidAppear: and the will/did disappear.
    [self _updateSlices];

    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;
    [view flashScrollIndicators];
}

@end
