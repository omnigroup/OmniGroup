// Copyright 2002-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/ColorSync/OAColorProfile.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSObject.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>

@class NSDictionary, NSMutableDictionary;
@class NSPrintInfo;

@interface OAColorProfile : NSObject <NSCopying>
{
    BOOL isMutable;
    void *rgbProfile, *cmykProfile, *grayProfile;
}

+ (OAColorProfile *)defaultDocumentProfile;
+ (OAColorProfile *)defaultDisplayProfile;
+ (OAColorProfile *)currentProfile;

+ (OAColorProfile *)defaultProofProfile;
+ (OAColorProfile *)workingCMYKProfile;
+ (NSArray *)proofingDeviceProfileNames;
+ (OAColorProfile *)proofProfileForDeviceProfileName:(NSString *)deviceProfileName;
+ (OAColorProfile *)proofProfileForPrintInfo:(NSPrintInfo *)printInfo;

+ (NSArray *)rgbProfileNames;
+ (NSArray *)cmykProfileNames;
+ (NSArray *)grayProfileNames;
+ (OAColorProfile *)colorProfileWithRGBNamed:(NSString *)rgbName cmykNamed:(NSString *)cmykName grayNamed:(NSString *)grayName;

+ (OAColorProfile *)colorProfileFromPropertyListRepresentation:(NSDictionary *)dict;
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
- (BOOL)_hasRGBSpace;
- (BOOL)_hasCMYKSpace;
- (BOOL)_hasGraySpace;
- (void)_setRGBColor:(NSColor *)aColor;
- (void)_setCMYKColor:(NSColor *)aColor;
- (void)_setGrayColor:(NSColor *)aColor;
- (void *)_rgbConversionWorldForOutput:(OAColorProfile *)aProfile;
- (void *)_cmykConversionWorldForOutput:(OAColorProfile *)aProfile;
- (void *)_grayConversionWorldForOutput:(OAColorProfile *)aProfile;

// For use by subclasses
- (void **)_cachedRGBColorWorldForOutput:(OAColorProfile *)aProfile;
- (void **)_cachedCMYKColorWorldForOutput:(OAColorProfile *)aProfile;
- (void **)_cachedGrayColorWorldForOutput:(OAColorProfile *)aProfile;
- (void *)_rgbProfile;
- (void *)_cmykProfile;
- (void *)_grayProfile;
@end

extern NSString *DefaultDocumentColorProfileDidChangeNotification;
extern NSString *ColorProofingDevicesDidChangeNotification;

