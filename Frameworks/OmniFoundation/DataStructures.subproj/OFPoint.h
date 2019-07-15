// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSGeometry.h>
#else
#import <CoreGraphics/CGGeometry.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class NSMutableDictionary, NSDictionary;

@interface OFPoint : NSObject <NSCopying /*, NSCoding*/>

+ (OFPoint *)pointWithPoint:(CGPoint)point;

- initWithPoint:(CGPoint)point;
- initWithString:(NSString *)string;

@property(nonatomic,readonly) CGPoint point;

- (NSMutableDictionary *)propertyListRepresentation;
+ (OFPoint *)pointFromPropertyListRepresentation:(NSDictionary *)dict;

@end

// Value transformer
extern NSString * const OFPointToPropertyListTransformerName;

NS_ASSUME_NONNULL_END

