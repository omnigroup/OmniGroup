// Copyright 2001-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OmniSystemInfoPreferenceClient.h"


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>

#import <OmniSystemInfo/OSUPreferences.h>
#import <OmniSystemInfo/OSUSystemConfigurationController.h>

RCS_ID("$Id$");

@interface OmniSystemInfoPreferenceClient ()
@property(nonatomic,strong) IBOutlet NSButton *includeHardwareButton;
@end

@implementation OmniSystemInfoPreferenceClient

- (BOOL)wantsAutosizing;
{
    return YES;
}

- (void)updateUI;
{
    BOOL enabled = [[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue] && [[OSUPreferences includeHardwareDetails] boolValue];
    [_includeHardwareButton setState:enabled];
}

- (IBAction)setValueForSender:(id)sender;
{
    if (sender == _includeHardwareButton) {
        BOOL enabled = [_includeHardwareButton state];
        [[OSUPreferences automaticSoftwareUpdateCheckEnabled] setBoolValue:enabled];
        [[OSUPreferences includeHardwareDetails] setBoolValue:enabled];
        [[OSUPreferences checkInterval] restoreDefaultValue]; // Leave this at whatever is in the defaults file (we might change the registered default if we switch to reporting a message of the day).
    }
}

// API

- (IBAction)showSystemConfigurationDetailsSheet:(id)sender;
{
    OSUSystemConfigurationController *configurationViewController = [[OSUSystemConfigurationController alloc] init];
    [configurationViewController runModalSheetInWindow:self.controlBox.window];
}

@end
