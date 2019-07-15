// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
#import <Security/Security.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSFilePromiseProvider.h>

@class NSImage;

NS_ASSUME_NONNULL_BEGIN

@interface OASecCertificateProxy : NSObject <NSPasteboardReading, NSPasteboardWriting, NSFilePromiseProviderDelegate>

- (instancetype)initWithCertificate:(SecCertificateRef)cert;
- (instancetype)initWithCertificate:(SecCertificateRef)cert hasPrivateKey:(BOOL)pka;

@property (readonly) SecCertificateRef certificate;

@property (readonly) BOOL hasPrivateKey;
@property (readonly) NSImage *icon;
@property (readonly) NSString *localizedDescription;

- (NSComparisonResult)compare:(id)other;

@end

NS_ASSUME_NONNULL_END
