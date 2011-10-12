// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniFileStore/OFSDAVFileManagerDelegate.h>
#import "OUICertificateTrustAlert.h"

extern NSString * const OUICertificateTrustUpdated;

typedef enum {
    OUIWebDAVConnectionValid,
    OUIWebDAVConnectionNotConfigured,
    OUIWebDAVNoInternetConnection,
    OUIWebDAVCertificateTrustIssue,
    OUIWebDAVOtherConnectionError
} OUIWebDAVConnectionValidity;

@class OFSFileManager;
@interface OUIWebDAVConnection : NSObject <OFSDAVFileManagerAuthenticationDelegate, OUICertificateTrustAlertDelegate> {
@private 
    NSURL *_address;
    NSString *_username;
    NSString *_password;
    
    OFSFileManager *_fileManager;
    NSURLAuthenticationChallenge *_authenticationChallenge;
    OUICertificateTrustAlert *_certAlert;
}

+ (OUIWebDAVConnection *)sharedConnection;
- (OUIWebDAVConnectionValidity)validateConnection;
- (void)close;
- (BOOL)trustAlertVisible;

@property (readwrite, retain) NSURL *address;
@property (readwrite, retain) NSString *username;
@property (readwrite, retain) NSString *password;
@property (readonly, retain) OFSFileManager *fileManager;
@property (readonly, retain) NSURLAuthenticationChallenge *authenticationChallenge;

@end
