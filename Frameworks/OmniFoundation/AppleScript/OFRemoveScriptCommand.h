// Copyright 2000-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSScriptCommand.h>

@class NSArray;

@interface OFRemoveScriptCommand : NSScriptCommand
@end

@interface NSObject (OFRemoveScriptCommand)
- (void)removeObjects:(NSArray *)objects fromPropertyWithKey:(NSString *)key;
@end
