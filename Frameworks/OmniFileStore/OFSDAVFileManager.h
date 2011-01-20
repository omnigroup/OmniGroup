// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSDAVFileManagerDelegate.h>

extern NSString * const OFSMobileMeHost;
extern NSString * const OFSTrustedSyncHostPreference;

@interface OFSDAVFileManager : OFSFileManager <OFSConcreteFileManager>

+ (NSString *)standardUserAgentString;
+ (void)setUserAgentDelegate:(id <OFSDAVFileManagerUserAgentDelegate>)delegate;
+ (id <OFSDAVFileManagerUserAgentDelegate>)userAgentDelegate;

+ (void)setAuthenticationDelegate:(id <OFSDAVFileManagerAuthenticationDelegate>)delegate;
+ (id <OFSDAVFileManagerAuthenticationDelegate>)authenticationDelegate;

+ (BOOL)isTrustedHost:(NSString *)host;
+ (void)setTrustedHost:(NSString *)host;
+ (void)removeTrustedHost:(NSString *)host;
@end
