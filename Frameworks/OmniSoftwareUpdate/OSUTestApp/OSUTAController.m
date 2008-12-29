// Copyright 2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUTAController.h"

#import "OSUChecker.h"
#import "OSUTAChecker.h"
#import "NSApplication-OSUSupport.h"
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>
#import <OmniAppKit/OmniAppKit.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/OmniGroup/Templates/Developer%20Tools/File%20Templates/%20Omni/OmniAppKit%20public%20class.pbfiletemplate/class.m 70671 2005-11-22 01:01:39Z kc $");


@implementation OSUTAController

@end


@implementation OSUTAController (DelegatesAndDataSources)

#pragma mark --
#pragma mark NSApplication delegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification;
{
    [[OFController sharedController] didInitialize];
    [[OFController sharedController] startedRunning];
    
    OSUTAChecker *checker = (OSUTAChecker *)[OSUChecker sharedUpdateChecker];
    OBASSERT([checker isKindOfClass:[OSUTAChecker class]]);
    Class checkerClass = [checker class];
    [[bundleIdentifierField cell] setPlaceholderString:[checkerClass defaultBundleIdentifier]];
    [[marketingVersionField cell] setPlaceholderString:[checkerClass defaultBundleMarketingVersionString]];
    [[buildVersionField cell] setPlaceholderString:[checkerClass defaultBundleBuildVersionString]];
    [[systemVersionField cell] setPlaceholderString:[checkerClass defaultUserVisibleSystemVersion]];
}

@end
