// Copyright 2002-2005, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>

@class NSDictionary, NSMutableDictionary;
@class NSPrintInfo;

@interface OAColorProfile : NSObject <NSCopying>
{
    BOOL isMutable;
    ColorSyncProfileRef rgbProfile, cmykProfile, grayProfile;
}

+ (instancetype)defaultDocumentProfile;
+ (instancetype)defaultDisplayProfile;
+ (instancetype)currentProfile;

+ (instancetype)defaultProofProfile;
+ (instancetype)workingCMYKProfile;
+ (NSArray *)proofingDeviceProfileNames;
+ (instancetype)proofProfileForDeviceProfileName:(NSString *)deviceProfileName;
+ (instancetype)proofProfileForPrintInfo:(NSPrintInfo *)printInfo;

+ (NSArray *)rgbProfileNames;
+ (NSArray *)cmykProfileNames;
+ (NSArray *)grayProfileNames;
+ (instancetype)colorProfileWithRGBNamed:(NSString *)rgbName cmykNamed:(NSString *)cmykName grayNamed:(NSString *)grayName;

+ (instancetype)colorProfileFromPropertyListRepresentation:(NSDictionary *)dict;
- (NSMutableDictionary *)propertyListRepresentation;

- (void)set;
- (void)unset;

- (BOOL)isEqualToProfile:(OAColorProfile *)otherProfile;

- (NSString *)rgbName;
- (NSString *)cmykName;
- (NSString *)grayName;
- (NSData *)rgbData;
- (NSData *)cmykData;
- (NSData *)grayData;

// For use by conversions
- (BOOL)_hasRGBSpace;
- (BOOL)_hasCMYKSpace;
- (BOOL)_hasGraySpace;
- (void)_setRGBColor:(NSColor *)aColor;
- (void)_setCMYKColor:(NSColor *)aColor;
- (void)_setGrayColor:(NSColor *)aColor;
- (ColorSyncTransformRef)_rgbConversionWorldForOutput:(OAColorProfile *)aProfile;
- (ColorSyncTransformRef)_cmykConversionWorldForOutput:(OAColorProfile *)aProfile;
- (ColorSyncTransformRef)_grayConversionWorldForOutput:(OAColorProfile *)aProfile;

// For use by subclasses
- (ColorSyncTransformRef*)_cachedRGBColorWorldForOutput:(OAColorProfile *)aProfile;
- (ColorSyncTransformRef*)_cachedCMYKColorWorldForOutput:(OAColorProfile *)aProfile;
- (ColorSyncTransformRef*)_cachedGrayColorWorldForOutput:(OAColorProfile *)aProfile;
- (ColorSyncProfileRef)_rgbProfile;
- (ColorSyncProfileRef)_cmykProfile;
- (ColorSyncProfileRef)_grayProfile;
@end

extern NSString * const OADefaultDocumentColorProfileDidChangeNotification;
extern NSString * const OAColorProofingDevicesDidChangeNotification;

