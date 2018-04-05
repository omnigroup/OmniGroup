// Copyright 2001-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUPreferenceClient.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>

#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/OSUController.h>
#import <OmniSoftwareUpdate/OSUSystemConfigurationController.h>

RCS_ID("$Id$");

typedef enum { Daily, Weekly, Monthly } CheckFrequencyMark;

@interface OSUPreferenceClient ()
@property(nonatomic,strong) IBOutlet NSButton *enableButton;
@property(nonatomic,strong) IBOutlet NSPopUpButton *frequencyPopup;
@property(nonatomic,strong) IBOutlet NSButton *checkNowButton;
@property(nonatomic,strong) IBOutlet NSButton *includeHardwareButton;
@property(nonatomic,strong) IBOutlet NSButton *learnMoreButton;
@end

@implementation OSUPreferenceClient

- (void)willBecomeCurrentPreferenceClient;
{
    if ([[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSEventModifierFlagOption)
        [self queueSelector:@selector(checkNow:) withObject:nil];
}

- (BOOL)wantsAutosizing;
{
    return YES;
}

- (void)updateUI;
{
    NSInteger checkFrequencyInDays, itemIndexToSelect;
    
    [_enableButton setState:[[OSUPreferences automaticSoftwareUpdateCheckEnabled] boolValue]];
    checkFrequencyInDays = [[OSUPreferences checkInterval] integerValue] / 24;

    if (checkFrequencyInDays > 27)
        itemIndexToSelect = [_frequencyPopup indexOfItemWithTag:Monthly];
    else if (checkFrequencyInDays > 6)
        itemIndexToSelect = [_frequencyPopup indexOfItemWithTag:Weekly];
    else
        itemIndexToSelect = [_frequencyPopup indexOfItemWithTag:Daily];
    [_frequencyPopup selectItemAtIndex:itemIndexToSelect];

    [_includeHardwareButton setState:[[OSUPreferences includeHardwareDetails] boolValue]];
}

- (IBAction)setValueForSender:(id)sender;
{
    if (sender == _enableButton) {
        [[OSUPreferences automaticSoftwareUpdateCheckEnabled] setBoolValue:[_enableButton state] != 0];
    } else if (sender == _frequencyPopup) {
        int checkFrequencyInHours;
        
        switch ([[sender selectedItem] tag]) {
            case Daily:
                checkFrequencyInHours = 24;
                break;
            default:
            case Weekly:
                checkFrequencyInHours = 24 * 7;
                break;
            case Monthly:
                checkFrequencyInHours = 24 * 28; // lunar months! or would some average days per month figure be better?
                break;
        }
        [[OSUPreferences checkInterval] setIntegerValue:checkFrequencyInHours];
    } else if (sender == _includeHardwareButton) {
        [[OSUPreferences includeHardwareDetails] setBoolValue:[_includeHardwareButton state] != 0];
    }
}

// API

- (IBAction)checkNow:(id)sender;
{
    [OSUController checkSynchronouslyWithUIAttachedToWindow:[[self controlBox] window]];
}

- (IBAction)showSystemConfigurationDetailsSheet:(id)sender;
{
    OSUSystemConfigurationController *configurationViewController = [[OSUSystemConfigurationController alloc] init];
    [configurationViewController runModalSheetInWindow:self.controlBox.window];
}

@end
