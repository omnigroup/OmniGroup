// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class ODOObject, ODOProperty;

typedef void (^ODOObjectPropertyChangeAction)(__kindof ODOObject *object, ODOProperty *property);

@interface ODOChangeActions : NSObject

- (void)append:(ODOObjectPropertyChangeAction)action;
- (void)prepend:(ODOObjectPropertyChangeAction)action;

@property(nonatomic,readonly) NSArray <ODOObjectPropertyChangeAction> *actions;

@end

typedef void (^ODOObjectSetDefaultAttributeValues)(__kindof ODOObject *object);

@interface ODOObjectSetDefaultAttributeValueActions : NSObject

- (void)addAction:(ODOObjectSetDefaultAttributeValues)action;

@property(nonatomic,readonly) NSArray <ODOObjectSetDefaultAttributeValues> *actions;

@end

NS_ASSUME_NONNULL_END
