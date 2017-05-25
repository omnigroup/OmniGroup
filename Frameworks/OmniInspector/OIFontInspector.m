// Copyright 2002-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIFontInspector.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

static void (*original_orderFront)(id self, SEL _cmd, id sender) = NULL;
static void (*original_orderOut)(id self, SEL _cmd, id sender) = NULL;

@implementation NSFontPanel (OIExtensions)

OBPerformPosing(^{
    Class self = objc_getClass("NSFontPanel");
    original_orderFront = (typeof(original_orderFront))OBReplaceMethodImplementationWithSelector(self, @selector(orderFront:), @selector(_replacement_orderFront:));
    original_orderOut = (typeof(original_orderOut))OBReplaceMethodImplementationWithSelector(self, @selector(orderOut:), @selector(_replacement_orderOut:));
});

- (void)_replacement_orderFront:sender;
{
    // OBS #19160 -- deleting a collection from the font panel puts you in a bad place.  Sadly, the -attachedSheet returns nil here (the ordering is getting called by NSApplication while setting up the sheet).  We check the sender instead... lame.
    if ([self attachedSheet] || !sender) {
	original_orderFront(self, _cmd, sender);
        return;
    }
    
    if ([self isVisible])
        [self orderOut:sender];
    else
	original_orderFront(self, _cmd, sender);
}

- (void)_replacement_orderOut:(id)sender;
{
    // This is for the bug in AppKit (the portion in OBS #19160 that can be reproduced in TextEdit).
    if ([self attachedSheet]) {
        NSBeep();
        return;
    }
    original_orderOut(self, _cmd, sender);
}

@end
