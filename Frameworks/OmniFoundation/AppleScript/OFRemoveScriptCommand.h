// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSScriptCommand.h>
#import <OmniBase/OBUtilities.h>

@class NSArray;

@interface OFRemoveScriptCommand : NSScriptCommand
@end

@interface NSObject (OFRemoveScriptCommand)
- (void)removeObjects:(NSArray *)objects fromPropertyWithKey:(NSString *)key forCommand:(NSScriptCommand *)command;
@end

@interface NSObject (OFRemoveScriptCommandDeprecated)
- (void)removeObjects:(NSArray *)objects fromPropertyWithKey:(NSString *)key OB_DEPRECATED_ATTRIBUTE;
@end

