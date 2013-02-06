// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIViewController.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_PARENT_VC(format, ...) NSLog(@"VC_CONTAINMENT %@: " format, [self class],## __VA_ARGS__)
#else
    #define DEBUG_PARENT_VC(format, ...)
#endif

@implementation OUIViewController
{
    CGRect _initialFrame;
    
    OUIViewControllerVisibility _visibility;
    BOOL _lastChangeAnimated;
    UIViewController *_unretained_parent; 

    // This is not redundant with parentViewController from UIViewController. UIViewController sets parentViewController in addChildViewController: BEFORE calling willMoveToParentViewController. We don't set _unretained_parent until the end of didMoveToParentViewController, so we can check for (a) consistency of the parent across the calls and (b) make sure we move through having no parent before getting a new parent.
    UIViewController *_unretained_prospective_parent;
}

#ifdef OMNI_ASSERTIONS_ON
static BOOL _parentVisibiityMatches(OUIViewController *self)
{
    UIViewController *parent = self->_unretained_prospective_parent;
    switch (self.visibility) {
        case OUIViewControllerVisibilityAppearing:
        case OUIViewControllerVisibilityVisible:
            // -[UIWindow setRootViewController:] provokes -viewWillAppear:, but that view controller doesn't have a parent.
            //OBASSERT(parent);
            if ([parent isKindOfClass:[OUIViewController class]]) {
                OUIViewController *properParent = (OUIViewController *)parent;
                return properParent.visibility == OUIViewControllerVisibilityVisible || (self.visibility == OUIViewControllerVisibilityAppearing && properParent.visibility == OUIViewControllerVisibilityAppearing);
            }
            break;
        case OUIViewControllerVisibilityHidden:
        case OUIViewControllerVisibilityDisappearing:
            // Nothing to check. We could just be temporarily getting out of the way, being removed from a parent that is sticking around, or our parent could also be going away.
            break;
        default:
            OBASSERT_NOT_REACHED("Cases above should be exhaustive.");
            break;
    }
    return YES;
}

static BOOL _viewControllerIsChildButNotInViewHiearchy(OUIViewController *self, UIViewController *child)
{
    return ([self.childViewControllers indexOfObjectIdenticalTo:child] != NSNotFound) && [child isViewLoaded] && ![child.view isDescendantOfView:self.view];
}
#endif

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;

    return self;
}

- (void)dealloc
{
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityHidden); // Did someone forget to hide us?
    [super dealloc];
}

@synthesize initialFrame = _initialFrame;
@synthesize visibility = _visibility;

- (BOOL)isChildViewController:(UIViewController *)child;
{
    DEBUG_PARENT_VC(@"In %s with child: %@", __func__, child);
    return [self.childViewControllers indexOfObjectIdenticalTo:child] != NSNotFound;
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    if (CGRectIsEmpty(_initialFrame) == NO)
        self.view.frame = _initialFrame;
}

// These hooks maintain visibility state, which is accessible by clients using the visibility property and is used in places to skip the adding of child view controllers when we aren't visible.

- (void)viewWillAppear:(BOOL)animated;
{
    DEBUG_PARENT_VC(@"In %s", __func__);
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityHidden);
    
    _visibility = OUIViewControllerVisibilityAppearing;
    _lastChangeAnimated = animated;
    
    [super viewWillAppear:animated];
    
    OBASSERT(_parentVisibiityMatches(self));
}

- (void)viewDidAppear:(BOOL)animated;
{
    DEBUG_PARENT_VC(@"In %s", __func__);

    // iOS 5 calls this method twice, sadly.
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityAppearing || _visibility == OUIViewControllerVisibilityVisible);
    
    OBPRECONDITION(_lastChangeAnimated == animated);

    _visibility = OUIViewControllerVisibilityVisible;

    [super viewDidAppear:animated];
    
    OBASSERT(_parentVisibiityMatches(self));
}

- (void)viewWillDisappear:(BOOL)animated;
{
    DEBUG_PARENT_VC(@"In %s", __func__);
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityVisible);

    _visibility = OUIViewControllerVisibilityDisappearing;
    _lastChangeAnimated = animated;

    [super viewWillDisappear:animated];
    
    OBASSERT(_parentVisibiityMatches(self));
}

- (void)viewDidDisappear:(BOOL)animated;
{
    DEBUG_PARENT_VC(@"In %s", __func__);
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityDisappearing);
    OBPRECONDITION(_lastChangeAnimated == animated);

    _visibility = OUIViewControllerVisibilityHidden;
    
    [super viewDidDisappear:animated];
    
    OBASSERT(_parentVisibiityMatches(self));
}

- (void)addChildViewController:(UIViewController *)child;
{
    DEBUG_PARENT_VC(@"In %s with child: %@", __func__, child);
    OBPRECONDITION([child isKindOfClass:[OUIViewController class]]); // All of our UIViewControllers should extend OUIViewController so we can track visibility and assert proper handling of view controller containment
    OBPRECONDITION([self.childViewControllers indexOfObjectIdenticalTo:child] == NSNotFound); // Don't double-add
    OBPRECONDITION(_visibility != OUIViewControllerVisibilityDisappearing); // Why are we adding a child view controller to a parent that is disappearing?
    
    [super addChildViewController:child];
}

- (void) removeFromParentViewController;
{
    DEBUG_PARENT_VC(@"In %s", __func__);
    [super removeFromParentViewController];
}

- (void)transitionFromViewController:(UIViewController *)fromViewController toViewController:(UIViewController *)toViewController duration:(NSTimeInterval)duration options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL finished))completion;
{
    DEBUG_PARENT_VC(@"In %s, transitioning from: %@, to: %@", __func__, fromViewController, toViewController);
    
    // Assertions based on comment in UIViewController.h in iOS 5, beta 4.
    OBPRECONDITION(_viewControllerIsChildButNotInViewHiearchy(self, fromViewController));
    OBPRECONDITION(_viewControllerIsChildButNotInViewHiearchy(self, toViewController));
    
    [super transitionFromViewController:fromViewController toViewController:toViewController duration:duration options:options animations:animations completion:completion];
}


- (void)willMoveToParentViewController:(UIViewController *)parent;
{
    DEBUG_PARENT_VC(@"In %s with parent: %@", __func__, parent);
    OBPRECONDITION((parent == nil && _unretained_parent != nil) || (parent != nil && _unretained_parent == nil)); // Must have a parent to leave it, or not have a parent before getting a new one
    
#ifdef OMNI_ASSERTIONS_ON
    if (parent == nil)
        OBPRECONDITION([self isViewLoaded] && ([self.view isDescendantOfView:_unretained_parent.view] /*|| ![[self view] superview]*/)); // If leaving parent, then our view should have been part of the parent's view hierarchy. /* The OG font inspector is in a different view hierarchy */ May want to end editing before the view is removed. 
#endif
    
    _unretained_prospective_parent = parent;
    [super willMoveToParentViewController:parent];
}
- (void)didMoveToParentViewController:(UIViewController *)parent;
{
    DEBUG_PARENT_VC(@"In %s with parent: %@", __func__, parent);
    OBPRECONDITION(parent == _unretained_prospective_parent);

#ifdef OMNI_ASSERTIONS_ON
    // View containment should be established by the time we finalize the move to the parent view controller:
    if (parent != nil)
        OBPRECONDITION([self isViewLoaded] && ([self.view isDescendantOfView:parent.view] /*|| ![[self view] superview]*/)); // Theory is that the child's view should be in the heirarchy and sized right before telling it to update itself.  /* The OG font inspector is in a different view hierarchy. */
#endif
    
    [super didMoveToParentViewController:parent];
    
    // We might like to nil _unretained_prospective_parent, but the view(Did|Will)(Appear|Disappear) calls can happen before or after the didMoveToParentViewController calls, depending on whether the transition is animated. We keep the prospective parent around so we can check our visibility against the prospective parent's. The precondition above ensures that our real parent matches the prospective one.
    // _unretained_prospective_parent = nil;
    _unretained_parent = parent;
    OBASSERT(_unretained_parent == self.parentViewController);
}
@end
