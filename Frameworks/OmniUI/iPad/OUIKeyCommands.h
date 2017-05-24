// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUIKeyCommands : NSObject

+ (nullable NSArray<UIKeyCommand *> *)keyCommandsForCategories:(nullable NSString *)categories; // Categories should be a comma separated list without whitespace
+ (nullable NSSet<NSString *> *)keyCommandSelectorNamesForCategories:(nullable NSString *)categories; // Categories should be a comma separated list without whitespace

+ (nullable NSArray<UIKeyCommand *> *)keyCommandsWithCategories:(nullable NSString *)categories NS_DEPRECATED_IOS(9_0, 10_0, "Use +keyCommandsForCategories: instead");

+ (NSString *)truncatedDiscoverabilityTitle:(NSString *)title;

@end

#pragma mark -

@protocol OUIKeyCommandProvider

@required
@property (nullable, nonatomic, readonly) NSString *keyCommandCategories;
@property (nullable, nonatomic, readonly) NSArray<UIKeyCommand *> *keyCommands;

@end

#pragma mark -

@interface UIResponder (OUIKeyCommandProvider)

- (BOOL)hasKeyCommandWithAction:(SEL)action;

@end

NS_ASSUME_NONNULL_END
