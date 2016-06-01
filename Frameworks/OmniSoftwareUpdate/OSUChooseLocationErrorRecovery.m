// Copyright 2009-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUChooseLocationErrorRecovery.h"

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>
#import <OmniSoftwareUpdate/OSUChecker.h>
#import "OSUErrors.h"
#import "OSUInstaller.h"

RCS_ID("$Id$");

@implementation OSUChooseLocationErrorRecovery

#pragma mark OFErrorRecovery implementation

+ (NSString *)defaultLocalizedRecoveryOption;
{
    return NSLocalizedStringFromTableInBundle(@"Choose Location\\U2026", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error recovery option - to let the user choose where to install the newly-downloaded update");
}

- (BOOL)isApplicableToError:(NSError *)error;
{
    if (![[error domain] isEqualToString:OSUErrorDomain] || [error code] != OSUBadInstallationDirectory)
        return NO;

    if (![[self object] respondsToSelector:@selector(chooseInstallationDirectory:)])
        return NO;
    
    return YES;
}

- (BOOL)attemptRecoveryFromError:(NSError *)error;
{
    NSString *installingLastTry = [[error userInfo] objectForKey:NSFilePathErrorKey];
    return [[self object] chooseInstallationDirectory:installingLastTry];
}

@end

