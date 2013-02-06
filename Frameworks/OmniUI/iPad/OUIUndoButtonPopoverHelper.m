// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIUndoButtonPopoverHelper.h>

RCS_ID("$Id$");

static OUIUndoButtonPopoverHelper *_SharedPopoverHelper = nil;

@implementation OUIUndoButtonPopoverHelper

+ (id)sharedPopoverHelper;
{
    OBPRECONDITION([NSThread isMainThread]);
    if (_SharedPopoverHelper == nil) {
        _SharedPopoverHelper = [[self alloc] init];
    }
    
    return _SharedPopoverHelper;
}

+ (void)setSharedPopoverHelper:(OUIUndoButtonPopoverHelper *)popoverHelper;
{
    if (popoverHelper != _SharedPopoverHelper) {
        [_SharedPopoverHelper release];
        _SharedPopoverHelper = [popoverHelper retain];
    }
}

- (BOOL)presentPopover:(UIPopoverController *)popover fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
{
    return [[OUIAppController controller] presentPopover:popover fromRect:rect inView:view permittedArrowDirections:arrowDirections animated:animated];
}

- (BOOL)presentPopover:(UIPopoverController *)popover fromBarButtonItem:(UIBarButtonItem *)item permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
{
    return [[OUIAppController controller] presentPopover:popover fromBarButtonItem:item permittedArrowDirections:arrowDirections animated:animated];
}

- (void)dismissPopover:(UIPopoverController *)popover animated:(BOOL)animated
{
    [[OUIAppController controller] dismissPopover:popover animated:animated];
}

- (void)dismissPopoverAnimated:(BOOL)animated;
{
    [[OUIAppController controller] dismissPopoverAnimated:animated];
}

@end
