// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniBase/OBUtilities.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray, NSData, NSError;

@interface OAInternetConfig : OFObject

+ (instancetype)internetConfig;

// Returns the CFBundleSignature of the main bundle. This method isn't InternetConfig-specific, really...
+ (FourCharCode)applicationSignature;

// Helper applications for URLs

- (nullable NSString *)helperApplicationForScheme:(nullable NSString *)scheme;
- (BOOL)launchURL:(nullable NSString *)urlString error:(NSError **)outError;

// API for sending email

- (BOOL)launchMailTo:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy blindCarbonCopy:(nullable NSString *)blindCarbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body attachments:(nullable NSArray <NSString *> *)attachmentFilenames error:(NSError **)outError;

// Convenience methods which call the above method

- (BOOL)launchMailTo:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body error:(NSError **)outError;
- (BOOL)launchMailTo:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy blindCarbonCopy:(nullable NSString *)blindCarbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
