// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSAppleEventDescriptor.h>

@interface NSAppleEventDescriptor (OFExtensions)
+ (NSAppleEventDescriptor *)descriptorWithFileURL:(NSURL *)furl;
@end

@interface NSDictionary (OFExtensions_NSAppleEventDescriptor)
+ (NSDictionary *)dictionaryWithUserRecord:(NSAppleEventDescriptor *)descriptor;
- (NSAppleEventDescriptor *)userRecordValue;
@end
