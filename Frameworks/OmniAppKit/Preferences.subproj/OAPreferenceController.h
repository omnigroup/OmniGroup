// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Preferences.subproj/OAPreferenceController.h 89466 2007-08-01 23:35:13Z kc $

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSGeometry.h>

@class NSArray, NSBundle, NSMutableArray, NSMutableDictionary;
@class NSBox, NSButton, NSImageView, NSMatrix, NSTabView, NSTextField, NSToolbar, NSView, NSWindow;
@class OAPreferenceClient, OAPreferenceClientRecord, OAPreferencesIconView, OAPreferencesShowAllIconView, OAPreferencesWindow;
@class OAPreferencesMultipleIconView;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet

typedef enum OAPreferencesViewStyle {
        OAPreferencesViewSingle = 0, // one client, so no navigation bar
        OAPreferencesViewMultiple = 1, // several clients, presented a la Mail or Terminal
        OAPreferencesViewCustomizable = 2 // many clients in one or more categories, presented a la System Prefs. 
} OAPreferencesViewStyle;

@interface OAPreferenceController : OFObject
{
    IBOutlet OAPreferencesWindow *window;
    IBOutlet NSBox *preferenceBox;
    IBOutlet NSView *globalControlsView;
    IBOutlet NSButton *helpButton;
    IBOutlet NSButton *returnToOriginalValuesButton;
    
    NSView *showAllIconsView; // not to be confused with the "Show All" button
    OAPreferencesIconView *multipleIconView;
    
    NSMutableArray *preferencesIconViews;
    NSMutableDictionary *categoryNamesToClientRecordsArrays;
    
    NSArray *_clientRecords;
    NSMutableDictionary *_clientByRecordIdentifier;
    NSString *_defaultKeySuffix;
    
    OAPreferencesViewStyle viewStyle;
    
    NSToolbar *toolbar;
    NSArray *defaultToolbarItems;
    NSArray *allowedToolbarItems;

    OAPreferenceClientRecord *nonretained_currentClientRecord;
    OAPreferenceClient *nonretained_currentClient;
    float idealWidth;
}

+ (OAPreferenceController *)sharedPreferenceController;
+ (NSArray *)allClientRecords;
+ (OAPreferenceClientRecord *)clientRecordWithShortTitle:(NSString *)shortTitle;
+ (OAPreferenceClientRecord *)clientRecordWithIdentifier:(NSString *)identifier;

// For subclassers
+ (NSString *)overrideNameForCategoryName:(NSString *)categoryName;
+ (NSString *)overrideLocalizedNameForCategoryName:(NSString *)categoryName bundle:(NSBundle *)bundle;

- initWithClientRecords:(NSArray *)clientRecords defaultKeySuffix:(NSString *)defaultKeySuffix;

// API
- (void)close;
- (NSWindow *)window;
- (void)setTitle:(NSString *)title;
- (void)setCurrentClientByClassName:(NSString *)name;
- (void)setCurrentClientRecord:(OAPreferenceClientRecord *)clientRecord;
- (NSArray *)clientRecords;
- (NSString *)defaultKeySuffix;
- (OAPreferenceClientRecord *)clientRecordWithShortTitle:(NSString *)shortTitle;
- (OAPreferenceClientRecord *)clientRecordWithIdentifier:(NSString *)identifier;
- (OAPreferenceClient *)clientWithShortTitle:(NSString *)shortTitle;
- (OAPreferenceClient *)clientWithIdentifier:(NSString *)identifier;
- (OAPreferenceClient *)currentClient;
- (void)iconView:(OAPreferencesIconView *)iconView buttonHitAtIndex:(unsigned int)index;
- (void)validateRestoreDefaultsButton;

// Actions
- (IBAction)showPreferencesPanel:(id)sender;
- (IBAction)restoreDefaults:(id)sender;
- (IBAction)showNextClient:(id)sender;
- (IBAction)showPreviousClient:(id)sender;
- (IBAction)setCurrentClientFromToolbarItem:(id)sender;
- (IBAction)showHelpForClient:(id)sender;

@end

BOOL OAOpenSystemPreferencePane(NSString *bundleIdentifier, NSString *tabIdentifier);

