// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFForwardObject.h>

RCS_ID("$Id$")

@implementation OFForwardObject

static IMP nsObjectForward = NULL;

+ (void)initialize
{
    Method method = class_getInstanceMethod([NSObject class], @selector(forward::));
    nsObjectForward = method_getImplementation(method);
    return;
}

- forward:(SEL)sel :(marg_list)args
{
    return nsObjectForward(self, _cmd, sel, args);
}

- (void)forwardInvocation:(NSInvocation *)invocation;
{
    [NSException raise:@"subclassResponsibility" format:@"%@ does not implement -%@", [(Class)(self->isa) description], NSStringFromSelector([invocation selector])];
}

@end

