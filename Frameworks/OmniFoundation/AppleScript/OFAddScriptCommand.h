// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSScriptCommand.h>

@class NSArray;

@interface OFAddScriptCommand : NSScriptCommand
@end

@protocol OFAddScriptCommandContainer
@optional
- (void)addObjects:(NSArray *)objects toPropertyWithKey:(NSString *)key forCommand:(NSScriptCommand *)command;
- (void)insertObjects:(NSArray *)objects inPropertyWithKey:(NSString *)key atIndex:(NSInteger)insertionIndex forCommand:(NSScriptCommand *)command;
@end
