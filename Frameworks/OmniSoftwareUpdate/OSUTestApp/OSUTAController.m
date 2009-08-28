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
#import <OmniSoftwareUpdate/OSUDownloadController.h>

RCS_ID("$Id$");

@class OSUInstaller;

// Preferences keys
static NSString *OSUInstallFromURLKey = @"installFrom";

@implementation OSUTAController

// Bring up a sheet to prompt for a URL, then install from it
- (IBAction)forceInstall:sender;
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:OSUInstallFromURLKey];
    if (![NSString isEmptyString:value])
        [urlPromptField setStringValue:value];
    
    [NSApp beginSheet:[urlPromptField window] modalForWindow:window modalDelegate:self didEndSelector:@selector(urlSheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

// Target of the buttons on the URL prompt sheet
- (IBAction)acceptURL:sender;
{
    NSString *value = [urlPromptField stringValue];
    if ([NSString isEmptyString:value])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:OSUInstallFromURLKey];
    else
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:OSUInstallFromURLKey];

    [[NSUserDefaults standardUserDefaults] autoSynchronize];
    
    if ([sender tag] == 0 && ![NSString isEmptyString:[urlPromptField stringValue]])
        [NSApp endSheet:[urlPromptField window] returnCode:NSRunStoppedResponse];
    else
        [NSApp endSheet:[urlPromptField window] returnCode:NSRunAbortedResponse];
}

- (IBAction)changeLicenseState:sender;
{
    [[OSUChecker sharedUpdateChecker] setLicenseType:[[licenseStatePopUp selectedItem] representedObject]];
}

@end


@implementation OSUTAController (DelegatesAndDataSources)

- (void)awakeFromNib
{
    [licenseStatePopUp removeAllItems];
    NSString *states[] = {
        OSULicenseTypeUnset,
        OSULicenseTypeNone,
        OSULicenseTypeRegistered,
        OSULicenseTypeRetail,
        OSULicenseTypeBundle,
        OSULicenseTypeTrial,
        OSULicenseTypeExpiring,
        nil
    };
    
    for(int i = 0; states[i]; i++) {
        [licenseStatePopUp addItemWithTitle:states[i]];
        if (i != 0) {
            // Leave 'unset' == nil
            [[licenseStatePopUp lastItem] setRepresentedObject:states[i]];
        }
    }
    
    [licenseStatePopUp selectItemWithTitle:OSULicenseTypeUnset];
}

#pragma mark --
#pragma mark NSApplication delegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification;
{
    [[OFController sharedController] didInitialize];
    [[OFController sharedController] startedRunning];
    
    OSUTAChecker *checker = (OSUTAChecker *)[OSUChecker sharedUpdateChecker];
    OBASSERT([checker isKindOfClass:[OSUTAChecker class]]);
    
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    
    [[bundleIdentifierField cell] setPlaceholderString:[[NSBundle mainBundle] bundleIdentifier]];
    [[marketingVersionField cell] setPlaceholderString:[infoDict objectForKey:@"CFBundleShortVersionString"]];
    [[buildVersionField cell] setPlaceholderString:[infoDict objectForKey:@"CFBundleVersion"]];
}

- (void)urlSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    [sheet orderOut:nil];
    
    if (returnCode == NSRunStoppedResponse) {
        NSURL *u = [NSURL URLWithString:[urlPromptField stringValue]];
        if (!u) {
            NSBeep();
            return;
        }
        
        NSError *err = nil;
        OSUDownloadController *dl = [[OSUDownloadController alloc] initWithPackageURL:u item:nil error:&err];
        if (err)
            [NSApp presentError:err modalForWindow:window];
        (void)dl;
    }
}

@end
