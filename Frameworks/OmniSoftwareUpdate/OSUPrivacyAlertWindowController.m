// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUPrivacyAlertWindowController.h"

#import <OmniAppKit/OmniAppKit.h>

#import <OmniSoftwareUpdate/OSUPreferences.h>

RCS_ID("$Id$");

@interface OSUPrivacyAlertWindowController ()
@property(nonatomic,strong) IBOutlet NSImageView *privacyNoticeAppIconImageView;
@property(nonatomic,strong) IBOutlet NSTextField *privacyNoticeTitleTextField;
@property(nonatomic,strong) IBOutlet NSTextField *privacyNoticeMessageTextField;
@property(nonatomic,strong) IBOutlet NSButton    *enableHardwareCollectionButton;
@end

@implementation OSUPrivacyAlertWindowController

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}


- (OSUPrivacyNoticeResult)runHavingSeenPreviousVersion:(BOOL)hasSeenPreviousVersion;
{
    NSPanel *privacyNoticePanel = (NSPanel *)self.window;
    
    NSString *titleFormat;
    if (hasSeenPreviousVersion) {
        // If we *had* seen the panel before, replace the title string
#if OSU_FULL
	titleFormat = NSLocalizedStringFromTableInBundle(@"This version of %@ sends additional information using your Internet connection (when active) to check for new and updated versions of itself.", @"OmniSoftwareUpdate", OMNI_BUNDLE, "text of dialog box informing user of change in software update query");
#else
	titleFormat = NSLocalizedStringFromTableInBundle(@"This version of %@ sends additional anonymous system information to The Omni Group.", @"OmniSystemInfo", OMNI_BUNDLE, "MAS-only: text of dialog box informing user of change in anonymous system info that will be sent");
#endif
    } else {
#if OSU_FULL
        // The xib version is for the OmniSoftwareUpdate version
        titleFormat = [_privacyNoticeTitleTextField stringValue];
#else
	titleFormat = NSLocalizedStringFromTableInBundle(@"%@ has the ability to automatically send anonymous system information to The Omni Group.", @"OmniSystemInfo", OMNI_BUNDLE, "MAS-only: text of dialog box title informing user before sending system info");
#endif
    }
    
#if !OSU_FULL
    // We could hide the button in this case, but then the layout would be goofy. Instead, we make the state of this switch our result instead of whether they hit OK or Show Preferences. We do need to update the title to not talk about updates.
    _enableHardwareCollectionButton.title = NSLocalizedStringFromTableInBundle(@"Send anonymous system information to The Omni Group", @"OmniSystemInfo", OMNI_BUNDLE, "MAS-only: label for switch in privacy alert to specify whether to send system info");
#endif

    NSString *appName = [[OAController sharedController] applicationName];
    [_privacyNoticeTitleTextField setStringValue:[NSString stringWithFormat:titleFormat, appName]];
    [_privacyNoticeMessageTextField setStringValue:[NSString stringWithFormat:[_privacyNoticeMessageTextField stringValue], appName]];
    [_privacyNoticeAppIconImageView setImage:[[NSApplication sharedApplication] applicationIconImage]];

    // Prepopulate the checkbox with your current setting.
    [_enableHardwareCollectionButton setState:[[OSUPreferences includeHardwareDetails] boolValue]];
    
    OBStrongRetain(self); // should be OK, but if we switch to having a non-modal sheet variant on a sheet, we will need to keep ourselves alive.
    OSUPrivacyNoticeResult rc = (OSUPrivacyNoticeResult)[[NSApplication sharedApplication] runModalForWindow:privacyNoticePanel];
    OBAutorelease(self);
    
    [privacyNoticePanel orderOut:nil];
    
    BOOL sendHardwareInfo = ([_enableHardwareCollectionButton state] == NSControlStateValueOn);
#if !OSU_FULL
    // In the normal version, returning OSUPrivacyNoticeResultShowPreferences leaves the default set to YES, but delays the check. In the MAS version, the checkbox controls whether we send info at all, so we need to poke the default here too (since we expect the two preferences to be in sync for the MAS version).
    [[OSUPreferences automaticSoftwareUpdateCheckEnabled] setBoolValue:sendHardwareInfo];
#endif
    // Store the hardware preference either way
    [[OSUPreferences includeHardwareDetails] setBoolValue:sendHardwareInfo];
    [[NSUserDefaults standardUserDefaults] synchronize]; // Make sure we don't lose this one, espeically if they turn it off!
    
    if (rc != OSUPrivacyNoticeResultOK) {
        OBASSERT(rc == OSUPrivacyNoticeResultShowPreferences);
        
        OAPreferenceController *prefsController = [OAPreferenceController sharedPreferenceController];
        [prefsController showPreferencesPanel:nil];
        [prefsController setCurrentClientByClassName:NSStringFromClass([OSUPreferences class])];
    }
    
    return rc;
}

#pragma mark - NSWindowController subclass

- (NSString *)windowNibName;
{
    return @"OSUPrivacyAlert";
}

- (id)owner;
{
    return self; // Used to find the nib
}

#pragma mark - Actions

- (IBAction)privacyNoticePanelOK:(id)sender;
{
    [[NSApplication sharedApplication] stopModalWithCode:OSUPrivacyNoticeResultOK];
}

- (IBAction)privacyNoticePanelShowPreferences:(id)sender;
{
    [[NSApplication sharedApplication] stopModalWithCode:OSUPrivacyNoticeResultShowPreferences];
}

@end
