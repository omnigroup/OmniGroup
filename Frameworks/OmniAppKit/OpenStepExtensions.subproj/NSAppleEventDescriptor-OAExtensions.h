// Copyright 2002-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSAppleEventDescriptor-OAExtensions.h 104581 2008-09-06 21:18:23Z kc $

#import <Foundation/NSAppleEventDescriptor.h>

@interface NSAppleEventDescriptor (OAExtensions)

// Why Apple dodn't write this convenience method, I don't know.
+ (NSAppleEventDescriptor *)descriptorWithAEDescNoCopy:(const AEDesc *)aeDesc;

@end

