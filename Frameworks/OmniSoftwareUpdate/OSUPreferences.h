// Copyright 2001-2006,2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniAppKit/OAPreferenceClient.h>

@class OSUItem;
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
+ (OFPreference *)ignoredUpdates;

+ (void)setItem:(OSUItem *)anItem isIgnored:(BOOL)shouldBeIgnored;
+ (BOOL)itemIsIgnored:(OSUItem *)anItem;

- (IBAction)checkNow:(id)sender;
- (IBAction)showSystemConfigurationDetailsSheet:(id)sender;
- (IBAction)dismissSystemConfigurationDetailsSheet:(id)sender;

@end
