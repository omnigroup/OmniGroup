// Copyright 2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIParentViewController.h>

RCS_ID("$Id$");

@implementation OUIParentViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;

    _children = [[NSMutableArray alloc] init];

    return self;
}

- (void)dealloc
{
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityHidden); // Did someone forget to hide us?
    
    [_children release];
    [super dealloc];
}

@synthesize  visibility = _visibility;

- (void)addChildViewController:(UIViewController *)child animated:(BOOL)animated;
{
    OBPRECONDITION([_children indexOfObjectIdenticalTo:child] == NSNotFound); // Don't double-add
    OBPRECONDITION([child isViewLoaded] && ([child.view isDescendantOfView:self.view] || ![[self view] superview])); // Theory is that the child's view should be in the heirarchy and sized right before telling it to update itself.  The OG font inspector is in a different view hierarchy
    
    [_children addObject:child];
    
    switch (_visibility) {
        case OUIViewControllerVisibilityHidden:
            // Nothing
            break;
        case OUIViewControllerVisibilityAppearing:
            // If *we* are in the middle of appearing, we have to pass this instead of 'animated' to avoid assertion in -viewDidAppear:.
            [child viewWillAppear:_lastChangeAnimated];
            // we'll send -viewDidAppear: when we get it ourselves
            break;
        case OUIViewControllerVisibilityVisible:
            // need to send both
            [child viewWillAppear:animated];
            [child viewDidAppear:animated];
            break;
        case OUIViewControllerVisibilityDisappearing:
            // The child should already have an effective 'hidden' state.
            OBASSERT_NOT_REACHED("If we need to handle this case, we'll need to avoid sending the child -viewDidDisappear: when we get it");
            break;
    }
}

- (void)removeChildViewController:(UIViewController *)child animated:(BOOL)animated;
{
    OBPRECONDITION([_children indexOfObjectIdenticalTo:child] != NSNotFound);
    OBPRECONDITION([child isViewLoaded] && ([child.view isDescendantOfView:self.view] || ![[self view] superview])); // Inverse of the 'add' rule, may want to end editing before the view is removed. The OG font inspector is in a different view hierarchy

    [_children removeObjectIdenticalTo:child];
    
    switch (_visibility) {
        case OUIViewControllerVisibilityHidden:
            // Nothing
            break;
        case OUIViewControllerVisibilityAppearing:
            OBASSERT_NOT_REACHED("We'd need to send it a did-appear, will disappear, did disappear.");
            break;
        case OUIViewControllerVisibilityVisible:
            // need to send both
            [child viewWillDisappear:animated];
            [child viewDidDisappear:animated];
            break;
        case OUIViewControllerVisibilityDisappearing:
            // Let it know it is gone already
            // If *we* are in the middle of disappearing, we have to pass this instead of 'animated' to avoid assertion in -viewDidAppear:.
            [child viewDidDisappear:_lastChangeAnimated];
            break;
    }
}

- (BOOL)isChildViewController:(UIViewController *)child;
{
    return [_children indexOfObjectIdenticalTo:child] != NSNotFound;
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidUnload;
{
    OBPRECONDITION(self.visibility == OUIViewControllerVisibilityHidden);
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated;
{
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityHidden);
    
    _visibility = OUIViewControllerVisibilityAppearing;
    _lastChangeAnimated = animated;
    
    [super viewWillAppear:animated];
    
    for (UIViewController *child in _children)
        [child viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated;
{
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityAppearing);
    OBPRECONDITION(_lastChangeAnimated == animated);

    _visibility = OUIViewControllerVisibilityVisible;

    [super viewDidAppear:animated];
    
    for (UIViewController *child in _children)
        [child viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated;
{
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityVisible);

    _visibility = OUIViewControllerVisibilityDisappearing;
    _lastChangeAnimated = animated;

    [super viewWillDisappear:animated];
    
    for (UIViewController *child in _children)
        [child viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    OBPRECONDITION(_visibility == OUIViewControllerVisibilityDisappearing);
    OBPRECONDITION(_lastChangeAnimated == animated);

    _visibility = OUIViewControllerVisibilityHidden;
    
    [super viewDidDisappear:animated];
    
    for (UIViewController *child in _children)
        [child viewDidDisappear:animated];
}

@end
