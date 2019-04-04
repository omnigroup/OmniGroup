// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAMoreInfoErrorRecovery.h>

#import <Foundation/Foundation.h>

#if OMNI_BUILDING_FOR_MAC
#import <AppKit/AppKit.h>
#elif OMNI_BUILDING_FOR_IOS
#import <UIKit/UIKit.h>
#endif

#import <OmniBase/OBBundle.h>
#import <OmniBase/macros.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC;

@interface OAMoreInfoErrorRecovery ()
@property (nonatomic, copy) NSURL *URL;
@end

@implementation OAMoreInfoErrorRecovery

- (id)initWithURL:(NSURL *)URL;
{
    if (!(self = [super initWithLocalizedRecoveryOption:nil object:nil])) {
        return nil;
    }
    
    _URL = [URL copy];
    
    return self;
}

#pragma mark OFErrorRecovery subclass

+ (NSString *)defaultLocalizedRecoveryOption;
{
    return NSLocalizedStringWithDefaultValue(@"More Info <error recovery>", @"OmniAppKit", OMNI_BUNDLE, @"More Info", @"error recovery option");
}

- (BOOL)attemptRecoveryFromError:(NSError *)error NS_EXTENSION_UNAVAILABLE_IOS("Opening URLs for error recovery requires UIApplication");
{
#if OMNI_BUILDING_FOR_MAC
    [[NSWorkspace sharedWorkspace] openURL:self.URL];
#elif OMNI_BUILDING_FOR_IOS
    [[UIApplication sharedApplication] openURL:self.URL options:@{} completionHandler:nil];
#elif OMNI_BUILDING_FOR_SERVER
    // nothing?
#else
    OBASSERT_NOT_REACHED(@"Unknown build platform");
#endif
    
    // Opening a URL did not do anything to recover from the error state in the app
    return NO;
}

@end
