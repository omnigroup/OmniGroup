// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFFileTypeDescription : NSObject

- initWithFileType:(NSString *)fileType;

@property (nonatomic, readonly) NSString *fileType;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSArray <NSString *> *pathExtensions;

// Some well-known types
@property(class,nonatomic,readonly) OFFileTypeDescription *plainText;

@end

NS_ASSUME_NONNULL_END
