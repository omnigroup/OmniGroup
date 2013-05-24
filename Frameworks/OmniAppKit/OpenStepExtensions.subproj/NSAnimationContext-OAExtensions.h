// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSAnimationContext.h>

typedef void (^OAAnimationGroup)(NSAnimationContext *context);

@interface NSAnimationContext (OAExtensions)
+ (void)runAnimationGroups:(OAAnimationGroup)group, ... NS_REQUIRES_NIL_TERMINATION;
@end

