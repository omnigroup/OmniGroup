// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIMinimalScrollNotifierImplementation.h>

#import "OUIInspectorBackgroundView.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG_curt) && defined(DEBUG)
    #define DEBUG_ANIM(format, ...) NSLog(@"ANIM: " format, ## __VA_ARGS__)
#else
    #define DEBUG_ANIM(format, ...)
#endif


static CGFloat _setSliceSizes(UIView *self, NSArray *_slices, NSSet *slicesToPostponeFrameSetting)
{
    CGFloat yOffset = 0.0;
    CGRect bounds = self.bounds;

    if ([_slices count] == 0)
        return yOffset;
    
    // Spacing between the header of the popover and the first slice (our slice nibs have their content jammed to the top, typically).
    yOffset += [[_slices objectAtIndex:0] paddingToInspectorTop];
    
    OUIInspectorSlice *previousSlice = nil;
    for (OUIInspectorSlice *slice in _slices) {
        // Don't fiddle with slices that have been stolen by embedding inspectors (OmniGraffle).
        UIView *sliceView = slice.view;
        if (sliceView.superview != self)
            continue;
        
        if (previousSlice)
            yOffset += [slice paddingToPreviousSlice:previousSlice remainingHeight:bounds.size.height - yOffset];
        
        CGFloat sideInset = [slice paddingToInspectorSides];
        
        // If we have exactly one slice and it is marked height-sizable, give it our full bounds. This is useful for cases where we have a slice wrapper for something that normally wouldn't be a slice but is to make other things work more easily (like the columns tab of the contents inspector in OO/iPad). May revisit this later.
        CGFloat sliceHeight;
        if ([_slices count] == 1 && (sliceView.autoresizingMask & UIViewAutoresizingFlexibleHeight)) {
            sliceHeight = bounds.size.height - ([slice paddingToInspectorTop] + [slice paddingToInspectorBottom]);
        } else {
            // Otherwise the slice should be a fixed height and we should use it.
            sliceHeight = CGRectGetHeight(sliceView.frame);
        }
        
        if (!slicesToPostponeFrameSetting || [slicesToPostponeFrameSetting member:slice] == nil)
            sliceView.frame = CGRectMake(CGRectGetMinX(bounds) + sideInset, yOffset, CGRectGetWidth(bounds) - 2*sideInset, sliceHeight);

        yOffset += sliceHeight;
        
        previousSlice = slice;
    }
    
    yOffset += [[_slices lastObject] paddingToInspectorBottom];
    
    return yOffset;
}

@interface OUIStackedSlicesInspectorPaneContentView : UIScrollView
{
@private
    OUIInspectorBackgroundView *_backgroundView;
    NSArray *_slices;
}

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
    
    CGFloat yOffset = _setSliceSizes(self, _slices, nil);
    
    self.contentSize = CGSizeMake(bounds.size.width, yOffset);
    self.scrollEnabled = yOffset > bounds.size.height;

    // Have to do this after the previous adjustments or the background view can get stuck scrolled part way down when we become unscrollable.
    _backgroundView.frame = self.bounds;
    
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
    [_scrollNotifier release];
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
    [slice willMoveToParentViewController:nil];
    if ([slice isViewLoaded] && slice.view.superview == view) {
        [slice.view removeFromSuperview]; // Only remove it if it is loaded and wasn't stolen by an embedding inspector (OmniGraffle).
    }
    [slice removeFromParentViewController];
}

@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices;
{
    DEBUG_ANIM(@"In setSlices on thread %@", [NSThread currentThread]);
    // TODO: Might want an 'animate' variant later. 
    if (OFISEQUAL(_slices, slices))
        return;
    
    // Terrible hack to delay change until previous animation completes
    if (_isAnimating) {
        [self performSelector:@selector(setSlices:) withObject:slices afterDelay:0];
        return;
    }
    
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;

    BOOL unembeddedSlices = [[slices lastObject] isViewLoaded] && [(OUIInspectorSlice *)([slices lastObject]) view].superview != view;

    // Establish view and view controller containment
    NSSet *oldSlices = [NSSet setWithArray:_slices];
    NSSet *newSlices = [NSSet setWithArray:slices];
    NSMutableSet *toBeOrphanedSlices = [NSMutableSet setWithSet:oldSlices];
    [toBeOrphanedSlices minusSet:newSlices];
    NSMutableSet *toBeAdoptedSlices = [NSMutableSet setWithSet:newSlices];
    [toBeAdoptedSlices minusSet:oldSlices];

    [_slices release];
    _slices = [[NSArray alloc] initWithArray:slices];

    if (!unembeddedSlices) {
        for (OUIInspectorSlice *slice in toBeOrphanedSlices) {
            [slice willMoveToParentViewController:nil];
        }
    }

    // Don't completely zero the alphas, or some slices will expect to be skipped when setting slice sizes.
    CGFloat newSliceInitialAlpha = [oldSlices count] > 0 ? 0.01 : 1.0; // Don't fade in on first display.
    for (OUIInspectorSlice *slice in toBeAdoptedSlices) {
        if (!unembeddedSlices) {
            [self addChildViewController:slice];
            // Add this once up front, but only if an embedding inspector hasn't stolen it from us (OmniGraffle). Not pretty, but that's how it is right now.
            if (slice.view.superview == nil) {
                slice.view.alpha = newSliceInitialAlpha;
                [view addSubview:slice.view];
            }
        }
    }
    
    _setSliceSizes(self.view, _slices, oldSlices); // any slices that are sticking around keep their old frames, so we can animate them to their new positions
    
    // Telling the view about the slices triggers [view setNeedsLayout]. The view's layoutSubviews loops over the slices in order and sets their frames.
    view.slices = _slices;
        
    void (^animationHandler)(void) = ^{
        DEBUG_ANIM(@"enqueuing began");
        _isAnimating = YES;

        // animate position of slices that were already showing (whose frames were left unchanged above)
        _setSliceSizes(self.view, _slices, nil);

        for (OUIInspectorSlice *slice in toBeOrphanedSlices) {
            if ([slice isViewLoaded] && slice.view.superview == view)
                slice.view.alpha = 0.0;
        }
        for (OUIInspectorSlice *slice in toBeAdoptedSlices) {
            slice.view.alpha = 1.0;
        }
    };
    
    void (^completionHandler)(BOOL finished) = ^(BOOL finished){
        for (OUIInspectorSlice *slice in toBeOrphanedSlices) {
            if ([slice isViewLoaded] && slice.view.superview == view) {
                [slice.view removeFromSuperview]; // Only remove it if it is loaded and wasn't stolen by an embedding inspector (OmniGraffle).
            }
            [slice removeFromParentViewController];
        }
        
        if (!unembeddedSlices) {
            for (OUIInspectorSlice *slice in toBeAdoptedSlices) {
                [slice didMoveToParentViewController:self];
            }
        }
        
        _isAnimating = NO;
        DEBUG_ANIM(@"Animation completed");
    };
    
    if ([_slices count] > 0) {
        UIViewAnimationOptions options = UIViewAnimationOptionTransitionNone |UIViewAnimationOptionAllowAnimatedContent;
        [UIView animateWithDuration:OUICrossFadeDuration delay:0 options:options animations:animationHandler completion:completionHandler];
    } else {
        animationHandler();
        completionHandler(NO);
    }
}

- (void)sliceSizeChanged:(OUIInspectorSlice *)slice;
{
    // TODO: It seems like we should be able to animate the resizing to avoid jumpy transitions.
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
        
        [_scrollNotifier release];
        _scrollNotifier = nil;
        view.delegate = nil;
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
    
    if (!_scrollNotifier)
        _scrollNotifier = [[OUIMinimalScrollNotifierImplementation alloc] init];
    view.delegate = _scrollNotifier;
    
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
    DEBUG_ANIM(@"viewDidUnload");
    
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
