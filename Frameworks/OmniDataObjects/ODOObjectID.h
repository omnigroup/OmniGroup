// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSURL;
@class ODOEntity;

@interface ODOObjectID : OBObject <NSCopying>
{
@private
    ODOEntity *_entity;
    id _primaryKey;
}

- (instancetype)initWithEntity:(ODOEntity *)entity primaryKey:(id)primaryKey;

@property (nonatomic, readonly) ODOEntity *entity;
@property (nonatomic, readonly) id primaryKey;

@end

NS_ASSUME_NONNULL_END
