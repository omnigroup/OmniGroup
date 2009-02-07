// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSProcessInfo-OFExtensions.h>

// This is not included in OmniBase.h since system.h shouldn't be used except when covering OS specific behaviour
#import <OmniBase/system.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$")

@implementation NSProcessInfo (OFExtensions)

#ifdef OMNI_ASSERTIONS_ON

static NSString *(*_original_hostName)(NSProcessInfo *self, SEL _cmd) = NULL;
static NSString *_replacement_hostName(NSProcessInfo *self, SEL _cmd)
{
    OBASSERT_NOT_REACHED("Do not call -[NSProcessInfo hostName] as it may hang with a long timeout if reverse DNS entries for the host's IP aren't configured.  Use OFHostName() instead.");
    return _original_hostName(self, _cmd);
}
+ (void)performPosing;
{
    _original_hostName = (typeof(_original_hostName))OBReplaceMethodImplementation(self, @selector(hostName), (IMP)_replacement_hostName);
}
#endif

- (NSNumber *)processNumber;
{
    // Don't assume the pid is 16 bits since it might be 32.
    return [NSNumber numberWithInt:getpid()];
}

@end
