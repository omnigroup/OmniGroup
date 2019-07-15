// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray, NSDictionary, NSString;

@interface OUIPaletteTheme : NSObject

@property (class, nonatomic, readonly) NSArray<OUIPaletteTheme *> *defaultThemes;

- (instancetype)initWithDictionary:(NSDictionary *)dict stringTable:(NSString *)stringTable bundle:(NSBundle *)bundle;

@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSArray *colors;

@end

NS_ASSUME_NONNULL_END
