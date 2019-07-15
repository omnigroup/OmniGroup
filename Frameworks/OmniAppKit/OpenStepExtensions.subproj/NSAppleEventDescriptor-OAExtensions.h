// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSAppleEventDescriptor.h>

@interface NSAppleEventDescriptor (OAExtensions)

// Why Apple dodn't write this convenience method, I don't know.
+ (NSAppleEventDescriptor *)newDescriptorWithAEDescNoCopy:(const AEDesc *)aeDesc;

@end

