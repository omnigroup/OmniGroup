// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>

@class NSDictionary, NSMutableDictionary;
@class NSPrintInfo;

NS_ASSUME_NONNULL_BEGIN

@interface OAColorProfile : NSObject <NSCopying>
{
    BOOL isMutable;
    ColorSyncProfileRef rgbProfile, cmykProfile, grayProfile;
}

+ (OAColorProfile*)defaultDocumentProfile;
+ (OAColorProfile*)defaultDisplayProfile;
+ (nullable OAColorProfile*)currentProfile;

+ (OAColorProfile*)defaultProofProfile;
+ (OAColorProfile*)workingCMYKProfile;
+ (NSArray<NSString*> *)proofingDeviceProfileNames;
+ (OAColorProfile*)proofProfileForDeviceProfileName:(NSString *)deviceProfileName;
+ (OAColorProfile*)proofProfileForPrintInfo:(NSPrintInfo *)printInfo;

+ (NSArray<NSString*> *)rgbProfileNames;
+ (NSArray<NSString*> *)cmykProfileNames;
+ (NSArray<NSString*> *)grayProfileNames;
+ (instancetype)colorProfileWithRGBNamed:(nullable NSString *)rgbName cmykNamed:(nullable NSString *)cmykName grayNamed:(nullable NSString *)grayName;

+ (instancetype)colorProfileFromPropertyListRepresentation:(NSDictionary<NSString*,id> *)dict;
- (NSMutableDictionary<NSString*,id> *)propertyListRepresentation;

- (void)set;
- (void)unset;

- (BOOL)isEqualToProfile:(OAColorProfile *)otherProfile;

- (NSString *)rgbName;
- (NSString *)cmykName;
- (NSString *)grayName;
- (nullable NSData *)rgbData;
- (nullable NSData *)cmykData;
- (nullable NSData *)grayData;

// For use by conversions
- (BOOL)_hasRGBSpace;
- (BOOL)_hasCMYKSpace;
- (BOOL)_hasGraySpace;
- (void)_setRGBColor:(NSColor *)aColor;
- (void)_setCMYKColor:(NSColor *)aColor;
- (void)_setGrayColor:(NSColor *)aColor;
- (ColorSyncTransformRef _Nullable)_rgbConversionWorldForOutput:(OAColorProfile *)aProfile CF_RETURNS_NOT_RETAINED;
- (ColorSyncTransformRef _Nullable)_cmykConversionWorldForOutput:(OAColorProfile *)aProfile CF_RETURNS_NOT_RETAINED;
- (ColorSyncTransformRef _Nullable)_grayConversionWorldForOutput:(OAColorProfile *)aProfile CF_RETURNS_NOT_RETAINED;

// For use by subclasses
- (ColorSyncTransformRef __nullable*__nullable)_cachedRGBColorWorldForOutput:(OAColorProfile *)aProfile;
- (ColorSyncTransformRef __nullable*__nullable)_cachedCMYKColorWorldForOutput:(OAColorProfile *)aProfile;
- (ColorSyncTransformRef __nullable*__nullable)_cachedGrayColorWorldForOutput:(OAColorProfile *)aProfile;
- (ColorSyncProfileRef)_rgbProfile CF_RETURNS_NOT_RETAINED;
- (ColorSyncProfileRef)_cmykProfile CF_RETURNS_NOT_RETAINED;
- (ColorSyncProfileRef)_grayProfile CF_RETURNS_NOT_RETAINED;
@end

extern NSString * const OADefaultDocumentColorProfileDidChangeNotification;
extern NSString * const OAColorProofingDevicesDidChangeNotification;

NS_ASSUME_NONNULL_END

