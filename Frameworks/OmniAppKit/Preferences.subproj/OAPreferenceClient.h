// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSUserDefaultsController.h>
#import <OmniFoundation/OFPreference.h> // Lots of subclasses don't import OmniFoundation.h

@class NSArray, NSMutableArray, NSDictionary, NSNotification, NSString;
@class NSBox, NSTextField, NSView;
@class OAPreferenceClientRecord, OAPreferenceController;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet

NS_ASSUME_NONNULL_BEGIN

@interface OAPreferenceClient : NSUserDefaultsController

- (instancetype)initWithPreferenceClientRecord:(OAPreferenceClientRecord *)clientRecord controller:(OAPreferenceController *)controller;
- (instancetype)initWithTitle:(NSString *)title defaultsArray:(NSArray *)defaultsArray controller:(OAPreferenceController *)controller NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithDefaults:(nullable NSUserDefaults *)defaults initialValues:(nullable NSDictionary<NSString *, id> *)initialValues NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

+ (NSString *)resetPreferencesMainPromptString;
+ (NSString *)resetPreferencesSecondaryPromptString;
+ (NSString *)resetButtonTitle;
+ (NSString *)cancelButtonTitle;

@property(readonly, nonatomic) NSString *title;
@property(readonly, nonatomic) OAPreferenceController *controller;

@property(retain, nonatomic) IBOutlet NSView *controlBox;
@property(retain, nonatomic) IBOutlet NSView *initialFirstResponder;
@property(retain, nonatomic) IBOutlet NSView *lastKeyView;

- (void)resetFloatValueToDefaultNamed:(NSString *)defaultName inTextField:(NSTextField *)textField;
- (void)resetIntValueToDefaultNamed:(NSString *)defaultName inTextField:(NSTextField *)textField;

// This is an action, so don't change its type
- (IBAction)restoreDefaults:(id)sender;
- (void)restoreDefaultsNoPrompt;
- (BOOL)haveAnyDefaultsChanged;

// The default implementations of these methods do nothing:  each subclass is expected to implement them.
- (void)updateUI;
- (IBAction)setValueForSender:(id)sender;
- (void)willBecomeCurrentPreferenceClient;
- (void)didBecomeCurrentPreferenceClient;
- (void)resignCurrentPreferenceClient;
    
// These are public so they can be subclassed.
- (void)valuesHaveChanged;
- (void)controlTextDidEndEditing:(NSNotification *)notification;

/// If true, then OAPreferenceController will set the frame of the controlBox to its fittingSize before adding the controlBox to a preference pane.
///
/// The default implementation returns NO. Clients should override to adopt autosizing. We log a warning if a client's nib uses autolayout but the client declines to use autosizing. This will let us audit each preference pane for autosizing as we work with them.
///
/// Before calling fittingSize and setting the frame on the controlBox, OAPreferenceController adds a fixed width constraint with priority `OAPreferenceClientControlBoxFixedWidthPriority`. This additional width constraint works to fix the width of the controlBox so that text fields can wrap correctly. Clients should add higher priority maximum width constraints of their own if they don't want that behavior.
///
/// OAPreferenceController will center the controlBox horizontally in the preference pane if its fittingSize is smaller than the ideal width of the preference pane.
@property (nonatomic, readonly) BOOL wantsAutosizing;

@end

NS_ASSUME_NONNULL_END
