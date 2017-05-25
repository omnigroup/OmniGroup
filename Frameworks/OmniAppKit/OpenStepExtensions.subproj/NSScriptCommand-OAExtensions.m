// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSScriptCommand-OAExtensions.h"

#import <OmniAppKit/NSApplication-OAExtensions.h>

RCS_ID("$Id$");

@implementation NSScriptCommand (OAExtensions)

static id (*original_executeCommand)(NSScriptCommand *self, SEL _cmd) = NULL;

static id replacement_executeCommand(NSScriptCommand *self, SEL _cmd)
{
    id result = original_executeCommand(self, _cmd);
    
    // The top-level autorelease pool doesn't get flushed for Apple Events, only for "real" events. Radar 15553008.
    [[NSApplication sharedApplication] flushTopLevelAutoreleasePool];
    
    return result;
}

OBPerformPosing(^{
    Class self = objc_getClass("NSScriptCommand");
    original_executeCommand = (typeof(original_executeCommand))OBReplaceMethodImplementation(self, @selector(executeCommand), (IMP)replacement_executeCommand);
});

@end
