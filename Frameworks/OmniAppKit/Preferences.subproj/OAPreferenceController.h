// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSGeometry.h>

@class NSArray, NSBundle;
@class NSToolbar, NSWindow;
@class OAPreferenceClient, OAPreferenceClientRecord, OAPreferencesIconView;

extern const NSLayoutPriority OAPreferenceClientControlBoxFixedWidthPriority;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet
#import <AppKit/NSToolbar.h>

typedef enum OAPreferencesViewStyle {
        OAPreferencesViewSingle = 0, // one client, so no navigation bar
        OAPreferencesViewMultiple = 1, // several clients, presented a la Mail or Terminal
        OAPreferencesViewCustomizable = 2 // many clients in one or more categories, presented a la System Prefs. 
} OAPreferencesViewStyle;

typedef void (^OAPreferenceClientChangeCompletion)(__kindof OAPreferenceClient *client);

@interface OAPreferenceController : OFObject <NSToolbarDelegate>

+ (instancetype)sharedPreferenceController;
+ (NSArray *)allClientRecords;
+ (OAPreferenceClientRecord *)clientRecordWithShortTitle:(NSString *)shortTitle;
+ (OAPreferenceClientRecord *)clientRecordWithIdentifier:(NSString *)identifier;

// For subclassers
+ (NSString *)overrideNameForCategoryName:(NSString *)categoryName;
+ (NSString *)overrideLocalizedNameForCategoryName:(NSString *)categoryName bundle:(NSBundle *)bundle;

- (instancetype)initWithClientRecords:(NSArray *)clientRecords defaultKeySuffix:(NSString *)defaultKeySuffix;

@property (nonatomic, copy) NSSet <NSString *> *hiddenPreferenceIdentifiers;

// API
- (void)close;
- (NSWindow *)window;
- (NSWindow *)windowIfLoaded; // doesn't for load the window
- (void)setTitle:(NSString *)title;
- (void)setCurrentClientByClassName:(NSString *)name;
- (void)setCurrentClientRecord:(OAPreferenceClientRecord *)clientRecord;
- (void)setCurrentClientByClassName:(NSString *)name completion:(OAPreferenceClientChangeCompletion)completion;
- (void)setCurrentClientRecord:(OAPreferenceClientRecord *)clientRecord completion:(OAPreferenceClientChangeCompletion)completion;
- (void)reloadCurrentClient;
- (void)resetInterface;
- (NSArray <OAPreferenceClientRecord *> *)clientRecords;
- (NSString *)defaultKeySuffix;
- (OAPreferenceClientRecord *)clientRecordWithShortTitle:(NSString *)shortTitle;
- (OAPreferenceClientRecord *)clientRecordWithIdentifier:(NSString *)identifier;
- (OAPreferenceClient *)clientWithShortTitle:(NSString *)shortTitle;
- (OAPreferenceClient *)clientWithIdentifier:(NSString *)identifier;
@property(nonatomic,strong,readonly) OAPreferenceClient *currentClient;
- (void)iconView:(OAPreferencesIconView *)iconView buttonHitAtIndex:(NSUInteger)index;
- (void)validateRestoreDefaultsButton;

// Actions
- (IBAction)showPreferencesPanel:(id)sender;
- (IBAction)restoreDefaults:(id)sender;
- (IBAction)showNextClient:(id)sender;
- (IBAction)showPreviousClient:(id)sender;
- (IBAction)setCurrentClientFromToolbarItem:(id)sender;
- (IBAction)showHelpForClient:(id)sender;

@property (strong, nonatomic) NSToolbar *toolbar;

@end

BOOL OAOpenSystemPreferencePane(NSString *bundleIdentifier, NSString *tabIdentifier);

