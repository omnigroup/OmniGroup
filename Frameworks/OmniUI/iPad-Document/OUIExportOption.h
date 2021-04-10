// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSString;
@class UIImage;

// This is a model class used to back the options added to the collection view.

NS_ASSUME_NONNULL_BEGIN

@interface OUIExportOption : NSObject <NSCopying>

- initWithFileType:(NSString *)fileType label:(NSString *)label image:(UIImage *)image requiresPurchase:(BOOL)requiresPurchase;

@property(nonatomic, readonly) UIImage *image;
@property(nonatomic, readonly) NSString *label;
@property(nonatomic, readonly) NSString *fileType;
@property(nonatomic, readonly) BOOL requiresPurchase;

@end

NS_ASSUME_NONNULL_END
