// Copyright 2002-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIColorInspector.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

static void (*original_orderFront)(id self, SEL _cmd, id sender) = NULL;

@implementation NSColorPanel (OIExtensions)

// So it turns out that if the color panel mode is 1-4, the color panel is created with the slider picker, which has a popup on it that grabs cmd-1 through cmd-4. We want those key equivalents for ourselves, so we need to keep the color panel from stealing them. The easiest (only?) way to do that is to make sure some other picker comes up first so we have a chance to use cmd-1 through cmd-4 in the menu bar. Mode 6 is the color wheel.
OBDidLoad(^{
    @autoreleasepool {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSInteger currentMode = [defaults integerForKey:@"NSColorPanelMode"];
        
        if (currentMode >= 1 && currentMode <= 4)
            [defaults setInteger:6 forKey:@"NSColorPanelMode"];
    }
});

OBPerformPosing(^{
    Class self = objc_getClass("NSColorPanel");
    original_orderFront = (typeof(original_orderFront))OBReplaceMethodImplementationWithSelector(self, @selector(orderFront:), @selector(_replacement_orderFront:));
});

- (void)toggleWindow:sender;
{
    if ([self isVisible])
        [self orderOut:sender];
    else
        [self orderFront:sender];
}

- (void)_replacement_orderFront:sender;
{
    // Allow applications to configure whether to show alpha w/o manually calling into NSColorPanel (and thus causing it to load its nib).  Done here so that it works regardless of whether we have the color panel in Licky or not.
    static BOOL configuredAlpha = NO;
    if (!configuredAlpha) {
        if ([[OFPreference preferenceForKey:@"OIColorInspectorShowsAlpha"] boolValue])
            [self setShowsAlpha:YES];
	configuredAlpha = YES;
    }
    
    original_orderFront(self, _cmd, sender);
}

@end
