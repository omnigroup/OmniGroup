// Copyright 1997-2005, 2007, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSGeometry.h>

@class NSArray, NSBundle, NSMutableArray, NSMutableDictionary;
@class NSBox, NSButton, NSImageView, NSMatrix, NSTabView, NSTextField, NSToolbar, NSView, NSWindow;
@class OAPreferenceClient, OAPreferenceClientRecord, OAPreferencesIconView, OAPreferencesWindow;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet
#import <AppKit/NSToolbar.h>

typedef enum OAPreferencesViewStyle {
        OAPreferencesViewSingle = 0, // one client, so no navigation bar
        OAPreferencesViewMultiple = 1, // several clients, presented a la Mail or Terminal
        OAPreferencesViewCustomizable = 2 // many clients in one or more categories, presented a la System Prefs. 
} OAPreferencesViewStyle;

@interface OAPreferenceController : OFObject <NSToolbarDelegate>
{
    OAPreferencesWindow *_window;
    NSBox *_nonretained_preferenceBox;
    NSView *_globalControlsView;
    NSButton *_nonretained_helpButton;
    NSButton *_nonretained_returnToOriginalValuesButton;
    
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
    CGFloat idealWidth;
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
- (NSWindow *)windowIfLoaded; // doesn't for load the window
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
- (void)iconView:(OAPreferencesIconView *)iconView buttonHitAtIndex:(NSUInteger)index;
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

