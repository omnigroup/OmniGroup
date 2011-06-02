// Copyright 2000-2005, 2007-2008, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniBase/OBUtilities.h>
#import <OmniAppKit/OAFeatures.h> // for OA_INTERNET_CONFIG_ENABLED

#if OA_INTERNET_CONFIG_ENABLED

@class /* Foundation     */ NSArray, NSData, NSError;
@class /* OmniAppKit     */ OAInternetConfigMapEntry;

@interface OAInternetConfig : OFObject
{
    void *internetConfigInstance;
    int permissionStatus;
}

+ (OAInternetConfig *)internetConfig;

// Returns the CFBundleSignature of the main bundle. This method isn't InternetConfig-specific, really...
+ (FourCharCode)applicationSignature;

// Extracts the user's iTools account name from InternetConfig.
- (NSString *)iToolsAccountName:(NSError **)outError;

// Helper applications for URLs

- (NSString *)helperApplicationForScheme:(NSString *)scheme;
- (BOOL)setApplicationCreatorCode:(FourCharCode)applicationCreatorCode name:(NSString *)applicationName forScheme:(NSString *)scheme error:(NSError **)outError;
- (BOOL)launchURL:(NSString *)urlString error:(NSError **)outError;

// Mappings between type/creator codes and filename extensions

- (NSArray *)mapEntries;
- (OAInternetConfigMapEntry *)mapEntryForFilename:(NSString *)filename;
- (OAInternetConfigMapEntry *)mapEntryForTypeCode:(long)fileTypeCode creatorCode:(long)fileCreatorCode hintFilename:(NSString *)filename;

// User interface access (launches InternetConfig preferences editor)

- (void)editPreferencesFocusOnKey:(NSString *)key;

// Low-level access

- (void)beginReadOnlyAccess;
- (void)beginReadWriteAccess;
- (void)endAccess;

/* returns an array of NSStrings enumerating the keys available via InternetConfig */
- (NSArray *)allPreferenceKeys;
- (NSData *)dataForPreferenceKey:(NSString *)preferenceKey error:(NSError **)outError;

// High level methods

- (BOOL)launchMailTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy subject:(NSString *)subject body:(NSString *)body error:(NSError **)outError;
- (BOOL)launchMailTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject body:(NSString *)body error:(NSError **)outError;

- (BOOL)launchMailTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject body:(NSString *)body attachments:(NSArray *)attachmentFilenames;

@end

#endif // OA_INTERNET_CONFIG_ENABLED
