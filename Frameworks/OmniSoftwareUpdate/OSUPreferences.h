// Copyright 2001-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OSUPreferences.h 78373 2006-08-17 02:14:23Z bungi $

#import <OmniAppKit/OAPreferenceClient.h>

@class NSButton, NSPopUpButton, NSTextField, NSTextView;
@class WebView;

@interface OSUPreferences : OAPreferenceClient
{
    IBOutlet NSTextField   *infoTextField;
    IBOutlet NSButton      *enableButton;
    IBOutlet NSPopUpButton *frequencyPopup;
    IBOutlet NSButton      *checkNowButton;
    IBOutlet NSButton      *includeHardwareButton;
    IBOutlet WebView       *systemConfigurationWebView;
}

// API
+ (OFPreference *)automaticSoftwareUpdateCheckEnabled;
+ (OFPreference *)checkInterval;
+ (OFPreference *)includeHardwareDetails;

- (IBAction)checkNow:(id)sender;
- (IBAction)showSystemConfigurationDetailsSheet:(id)sender;
- (IBAction)dismissSystemConfigurationDetailsSheet:(id)sender;

@end
