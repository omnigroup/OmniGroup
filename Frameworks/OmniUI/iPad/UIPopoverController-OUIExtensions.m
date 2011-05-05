// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "UIPopoverController-OUIExtensions.h"

RCS_ID("$Id$");

@implementation UIPopoverController (OUIExtensions)

@end

#if 0 && defined(DEBUG_bungi)
    #define DEBUG_POPOVER_CONTENT_SIZE 1
#else
    #define DEBUG_POPOVER_CONTENT_SIZE 0
#endif

#if DEBUG_POPOVER_CONTENT_SIZE

// Override and log on many of the popover content size methods (though not all). We hardcode the set that are implemented at this point in time rather than trying to be clever and enumerate the runtime and keep a hash of stuff we've replaced.
// 0x00b8f3b6  -[UIPopoverController popoverContentSize]
// 0x00b8e7f8  -[UIPopoverController setPopoverContentSize:]
// 0x00b8f48a  -[UIPopoverController setPopoverContentSize:animated:]
// 0x008f59fa  -[UIViewController contentSizeForViewInPopoverView]
// 0x008f9064  -[UIViewController contentSizeForViewInPopover]
// 0x008f908c  -[UIViewController setContentSizeForViewInPopover:]
// 0x00902425  -[UINavigationController setContentSizeForViewInPopover:]
// 0x00902363  -[UINavigationController contentSizeForViewInPopover]
// 0x00c109c6  -[UIPrintStatusJobsViewController contentSizeForViewInPopover]
// 0x050dbc33  -[ABPeoplePickerNavigationController setContentSizeForViewInPopover:]

// UIPopoverController
static CGSize (*_original_UIPopoverController_popoverContentSize)(UIPopoverController *self, SEL _cmd) = NULL;
static void (*_original_UIPopoverController_setPopoverContentSize)(UIPopoverController *self, SEL _cmd, CGSize size) = NULL;
static void (*_original_UIPopoverController_setPopoverContentSizeAnimated)(UIPopoverController *self, SEL _cmd, CGSize size, BOOL animated) = NULL;

static CGSize _replacement_UIPopoverController_popoverContentSize(UIPopoverController *self, SEL _cmd)
{
    NSLog(@">>> -[%@ %@]", [self shortDescription], NSStringFromSelector(_cmd));
    CGSize size = _original_UIPopoverController_popoverContentSize(self, _cmd);
    NSLog(@"<<< -[%@ %@] --> %@", [self shortDescription], NSStringFromSelector(_cmd), NSStringFromCGSize(size));
    return size;
}
static void _replacement_UIPopoverController_setPopoverContentSize(UIPopoverController *self, SEL _cmd, CGSize size)
{
    NSLog(@">>> -[%@ %@] <-- %@", [self shortDescription], NSStringFromSelector(_cmd), NSStringFromCGSize(size));
    _original_UIPopoverController_setPopoverContentSize(self, _cmd, size);
    NSLog(@"<<< -[%@ %@]", [self shortDescription], NSStringFromSelector(_cmd));
}
static void _replacement_UIPopoverController_setPopoverContentSizeAnimated(UIPopoverController *self, SEL _cmd, CGSize size, BOOL animated)
{
    NSLog(@">>> -[%@ %@] <-- %@, animated:%d", [self shortDescription], NSStringFromSelector(_cmd), NSStringFromCGSize(size), animated);
    _original_UIPopoverController_setPopoverContentSizeAnimated(self, _cmd, size, animated);
    NSLog(@"<<< -[%@ %@]", [self shortDescription], NSStringFromSelector(_cmd));
}

// UIViewController
static CGSize (*_original_UIViewController_contentSizeForViewInPopoverView)(UIView *self, SEL _cmd) = NULL;
static CGSize (*_original_UIViewController_contentSizeForViewInPopover)(UIView *self, SEL _cmd) = NULL;
static void (*_original_UIViewController_setContentSizeForViewInPopover)(UIPopoverController *self, SEL _cmd, CGSize size) = NULL;

static CGSize _replacement_UIViewController_contentSizeForViewInPopoverView(UIView *self, SEL _cmd)
{
    NSLog(@">>> -[%@ %@]", [self shortDescription], NSStringFromSelector(_cmd));
    CGSize size = _original_UIViewController_contentSizeForViewInPopoverView(self, _cmd);
    NSLog(@"<<< -[%@ %@] --> %@", [self shortDescription], NSStringFromSelector(_cmd), NSStringFromCGSize(size));
    return size;
}
static CGSize _replacement_UIViewController_contentSizeForViewInPopover(UIView *self, SEL _cmd)
{
    NSLog(@">>> -[%@ %@]", [self shortDescription], NSStringFromSelector(_cmd));
    CGSize size = _original_UIViewController_contentSizeForViewInPopover(self, _cmd);
    NSLog(@"<<< -[%@ %@] --> %@", [self shortDescription], NSStringFromSelector(_cmd), NSStringFromCGSize(size));
    return size;
}
static void _replacement_UIViewController_setContentSizeForViewInPopover(UIPopoverController *self, SEL _cmd, CGSize size)
{
    NSLog(@">>> -[%@ %@] <-- %@", [self shortDescription], NSStringFromSelector(_cmd), NSStringFromCGSize(size));
    _original_UIViewController_setContentSizeForViewInPopover(self, _cmd, size);
    NSLog(@"<<< -[%@ %@]", [self shortDescription], NSStringFromSelector(_cmd));
}

// UINavigationController
static CGSize (*_original_UINavigationController_contentSizeForViewInPopover)(UIView *self, SEL _cmd) = NULL;
static void (*_original_UINavigationController_setContentSizeForViewInPopover)(UIPopoverController *self, SEL _cmd, CGSize size) = NULL;

static CGSize _replacement_UINavigationController_contentSizeForViewInPopover(UIView *self, SEL _cmd)
{
    NSLog(@">>> -[%@ %@]", [self shortDescription], NSStringFromSelector(_cmd));
    CGSize size = _original_UINavigationController_contentSizeForViewInPopover(self, _cmd);
    NSLog(@"<<< -[%@ %@] --> %@", [self shortDescription], NSStringFromSelector(_cmd), NSStringFromCGSize(size));
    return size;
}
static void _replacement_UINavigationController_setContentSizeForViewInPopover(UIPopoverController *self, SEL _cmd, CGSize size)
{
    NSLog(@">>> -[%@ %@] <-- %@", [self shortDescription], NSStringFromSelector(_cmd), NSStringFromCGSize(size));
    _original_UINavigationController_setContentSizeForViewInPopover(self, _cmd, size);
    NSLog(@"<<< -[%@ %@]", [self shortDescription], NSStringFromSelector(_cmd));
}

static void OUIPopoverControllerPerformPosing(void) __attribute__((constructor));
static void OUIPopoverControllerPerformPosing(void)
{    
#define REPL(cls, sel, func) \
    _original_ ## cls ## _ ## func = (typeof(_original_ ## cls ## _ ## func))OBReplaceMethodImplementation(NSClassFromString((id)CFSTR(#cls)), @selector(sel), (IMP)_replacement_ ## cls ## _ ## func)
    
    REPL(UIPopoverController, popoverContentSize, popoverContentSize);
    REPL(UIPopoverController, setPopoverContentSize:, setPopoverContentSize);
    REPL(UIPopoverController, setPopoverContentSize:animated:, setPopoverContentSizeAnimated);
    
    REPL(UIViewController, contentSizeForViewInPopoverView, contentSizeForViewInPopoverView);
    REPL(UIViewController, contentSizeForViewInPopover, contentSizeForViewInPopover);
    REPL(UIViewController, setContentSizeForViewInPopover:, setContentSizeForViewInPopover);
    
    REPL(UINavigationController, contentSizeForViewInPopover, contentSizeForViewInPopover);
    REPL(UINavigationController, setContentSizeForViewInPopover:, setContentSizeForViewInPopover);
}

#endif
