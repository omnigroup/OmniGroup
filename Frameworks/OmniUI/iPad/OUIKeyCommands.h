// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUIKeyCommands : NSObject

+ (nullable NSArray<UIKeyCommand *> *)keyCommandsForCategories:(nullable NSOrderedSet<NSString *> *)categories;
+ (nullable NSSet<NSString *> *)keyCommandSelectorNamesForCategories:(nullable NSOrderedSet<NSString *> *)categories;
+ (nullable NSSet<NSString *> *)keyCommandSelectorNamesForKeyCommands:(nullable NSArray<UIKeyCommand *> *)keyCommands;

+ (NSString *)truncatedDiscoverabilityTitle:(NSString *)title;

@end

#pragma mark -

@protocol OUIKeyCommandProvider

@required
@property (nullable, nonatomic, readonly) NSOrderedSet<NSString *> *keyCommandCategories;
@property (nullable, nonatomic, readonly) NSArray<UIKeyCommand *> *keyCommands;

@end

#pragma mark -

@interface UIResponder (OUIKeyCommandProvider)

- (BOOL)hasKeyCommandWithAction:(SEL)action;

@end

NS_ASSUME_NONNULL_END
