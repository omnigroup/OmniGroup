// Copyright 2000-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Carbon/OAInternetConfig.h 104581 2008-09-06 21:18:23Z kc $

#import <OmniFoundation/OFObject.h>
#import <OmniBase/OBUtilities.h>

@class /* Foundation     */ NSArray, NSData, NSError;
@class /* OmniAppKit     */ OAInternetConfigMapEntry;

@interface OAInternetConfig : OFObject
{
    void *internetConfigInstance;
    int permissionStatus;
}

+ (OAInternetConfig *)internetConfig;

// Returns the CFBundleSignature of the main bundle. This method isn't InternetConfig-specific, really...
+ (unsigned long)applicationSignature;

// Extracts the user's iTools account name from InternetConfig.
- (NSString *)iToolsAccountName:(NSError **)outError;

// Helper applications for URLs

- (NSString *)helperApplicationForScheme:(NSString *)scheme;
- (BOOL)setApplicationCreatorCode:(long)applicationCreatorCode name:(NSString *)applicationName forScheme:(NSString *)scheme error:(NSError **)outError;
- (BOOL)launchURL:(NSString *)urlString error:(NSError **)outError;

// Download folder

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5  // Uses API deprecated on 10.5
// You should probably use NSSearchPathForDirectoriesInDomains(...NSDownloadsDirectory...) instead
- (NSString *)downloadFolderPath:(NSError **)outError OB_DEPRECATED_ATTRIBUTE;
#endif

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
