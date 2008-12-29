// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OBObject : NSObject
@end


@class NSDictionary, NSMutableDictionary;

@interface NSObject (OBDebuggingExtensions)
- (NSMutableDictionary *)debugDictionary;
- (NSString *)shortDescription;
@end

@interface OBObject (OBDebugging)
- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(NSUInteger)level;
- (NSString *)description;
@end
