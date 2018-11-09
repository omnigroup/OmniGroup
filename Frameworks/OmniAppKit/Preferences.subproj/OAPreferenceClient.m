// Copyright 1997-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPreferenceClient.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSBundle-OAExtensions.h>
#import <OmniAppKit/OAPreferenceController.h>
#import <OmniAppKit/OAPreferenceClientRecord.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@interface OAPreferenceClient () {
  @private
    NSArray *_topLevelObjects;
    NSView *_controlBox;
    NSView *_initialFirstResponder;
    NSView *_lastKeyView;
    
    OAPreferenceController *_nonretained_controller;
    NSString *_title;
    NSMutableArray *_preferences;
}

@end

#pragma mark -

@implementation OAPreferenceClient

- (instancetype)initWithPreferenceClientRecord:(OAPreferenceClientRecord *)clientRecord controller:(OAPreferenceController *)controller;
{
    NSMutableArray *defaultsArray = [[[[clientRecord defaultsDictionary] allKeys] mutableCopy] autorelease];
    if (!defaultsArray)
        defaultsArray = [NSMutableArray array];
    
    NSArray *recordDefaultsArray = [clientRecord defaultsArray];
    if (recordDefaultsArray)
        [defaultsArray addObjectsFromArray:recordDefaultsArray];
        
    if (!(self = [self initWithTitle:[clientRecord title] defaultsArray:defaultsArray controller:controller]))
        return nil;
    
    NSString *nibName = [clientRecord nibName];
    if (nibName != nil) {
        NSArray *objects;
        if (![[NSBundle bundleForClass:[self class]] loadNibNamed:nibName owner:self topLevelObjects:&objects])
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Failed to load nib for preference client" userInfo:nil];
        
        _topLevelObjects = [objects retain];
    }

    return self;
}

/*" Creates a new preferences client (with the specified title), which manipulates the specified defaults. "*/
- (instancetype)initWithTitle:(NSString *)title defaultsArray:(NSArray *)defaultsArray controller:(OAPreferenceController *)controller;
{
    OBPRECONDITION(![NSString isEmptyString:title]);
    OBPRECONDITION(controller);
    
    NSString *defaultKeySuffix = [controller defaultKeySuffix];
    NSArray *keys;
    if (![NSString isEmptyString:defaultKeySuffix]) {
        NSMutableArray *clonedKeys = [NSMutableArray array];
        NSMutableDictionary *clonedDefaultRegistration = [NSMutableDictionary dictionary];
        
        for (NSString *key in defaultsArray) {
            // Register default values for the cloned preferences
            OFPreference *basePreference = [OFPreference preferenceForKey:key];
            id defaultValue = [basePreference defaultObjectValue];
            OBASSERT(defaultValue != nil);
            key = [key stringByAppendingFormat:@"-%@", defaultKeySuffix];
            if (defaultValue)
                [clonedDefaultRegistration setObject:defaultValue forKey:key];
            [clonedKeys addObject:key];
        }
        [[NSUserDefaults standardUserDefaults] registerDefaults:clonedDefaultRegistration];
        [OFPreference recacheRegisteredKeys];
        keys = clonedKeys;
    } else {
        keys = defaultsArray;
    }
    
    NSMutableArray *preferences = [NSMutableArray array];
    for (NSString *key in keys) {
        OFPreference *preference = [OFPreference preferenceForKey:key];
        OBASSERT(preference);
        
#ifdef OMNI_ASSERTIONS_ON
        NSString *suffix = [NSString stringWithFormat:@"-%@", [controller defaultKeySuffix]]; // can't be in the macro invocation or it gets confused by ','
        OBPRECONDITION([NSString isEmptyString:[controller defaultKeySuffix]] || [[preference key] hasSuffix:suffix]);
#endif
        
        if (![preferences containsObjectIdenticalTo:preference]) {
            [preferences addObject:preference];
            [preference setController:self key:@"values"];
        }
    }

    OFPreferenceWrapper *defaults = [OFPreferenceWrapper sharedPreferenceWrapper];
    
    // Gather the initial values (not in the loop above since subclasses might have done something in -addPreference:)
    NSMutableDictionary *initialValues = [NSMutableDictionary dictionary];
    for (OFPreference *preference in preferences) {
	id value = [preference defaultObjectValue];
	OBASSERT(value, "Preference with key \"%@\" has no default value", preference.key); // Avoid raise, but this is really invalid.
	if (value)
	    [initialValues setObject:value forKey:[preference key]];
    }

    // Giving NSUserDefaultsController a wrapper that goes through our OFPreference stuff.  Iffy...
    if (!(self = [super initWithDefaults:(NSUserDefaults *)defaults initialValues:initialValues]))
        return nil;

    _nonretained_controller = controller;
    _title = [title copy];
    _preferences = [preferences mutableCopy];
    
    return self;
}

- (instancetype)initWithDefaults:(nullable NSUserDefaults *)defaults initialValues:(nullable NSDictionary<NSString *, id> *)initialValues NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (void)dealloc;
{
    [_controlBox release];
    [_initialFirstResponder release];
    [_lastKeyView release];
    [_title release];
    [_preferences release];
    [_topLevelObjects release];
    [super dealloc];
}

// API

+ (NSString *)resetPreferencesMainPromptString;
{
    return NSLocalizedStringFromTableInBundle(@"Reset %@ preferences to their original values?", @"OmniAppKit", [OAPreferenceClient bundle], "message text for reset-to-defaults alert");
}

+ (NSString *)resetPreferencesSecondaryPromptString;
{
    return NSLocalizedStringFromTableInBundle(@"Choosing Reset will restore all settings in this pane to the state they were in when %@ was first installed.", @"OmniAppKit", [OAPreferenceClient bundle], "informative text for reset-to-defaults alert");
}

+ (NSString *)resetButtonTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Reset", @"OmniAppKit", [OAPreferenceClient bundle], "alert panel button");
}

+ (NSString *)cancelButtonTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", [OAPreferenceClient bundle], "alert panel button");
}

@synthesize controlBox = _controlBox;
@synthesize initialFirstResponder = _initialFirstResponder;
@synthesize lastKeyView = _lastKeyView;
@synthesize title = _title;
@synthesize controller = _nonretained_controller;

/*" Restores all defaults for this preference client to their original installation values. "*/
- (IBAction)restoreDefaults:(id)sender;
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:[[self class] resetPreferencesMainPromptString], _title];
    alert.informativeText = [NSString stringWithFormat:[[self class] resetPreferencesSecondaryPromptString], [[NSProcessInfo processInfo] processName]];
    [alert addButtonWithTitle:[[self class] resetButtonTitle]];
    [alert addButtonWithTitle:[[self class] cancelButtonTitle]];
    [alert beginSheetModalForWindow:_controlBox.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn)
            return;
        [self restoreDefaultsNoPrompt];
        [self valuesHaveChanged];
    }];
}

- (void)restoreDefaultsNoPrompt;
{
    [self revertToInitialValues:nil];
    OBPOSTCONDITION([self haveAnyDefaultsChanged] == NO);
}

- (BOOL)haveAnyDefaultsChanged;
{
    for (OFPreference *aPreference in _preferences) {
        if ([aPreference hasNonDefaultValue]) {
#ifdef DEBUG_kc0
            NSLog(@"-%s: non-default value: '%@' = '%@'", _cmd, [aPreference key], [aPreference objectValue]);
#endif
            return YES;
        }
    }

    return [self hasUnappliedChanges]; // Checks if there are editors active
}

- (void)resetFloatValueToDefaultNamed:(NSString *)defaultName inTextField:(NSTextField *)textField;
{
    OFPreference *preference = [OFPreference preferenceForKey: defaultName];
    [preference restoreDefaultValue];
    [textField setFloatValue:[preference floatValue]];
    NSBeep();
}

- (void)resetIntValueToDefaultNamed:(NSString *)defaultName inTextField:(NSTextField *)textField;
{
    OFPreference *preference = [OFPreference preferenceForKey: defaultName];
    [preference restoreDefaultValue];
    [textField setIntegerValue:[preference integerValue]];
    NSBeep();
}


// Subclass me!

/*" Updates the UI to reflect the current defaults. "*/
- (void)updateUI;
{
}

/*" Updates defaults for a modified UI element (the sender). "*/
- (IBAction)setValueForSender:(id)sender;
{
}

/*" Called when the receiver is about to become the current client.  This can be used to register for notifications used to update the UI for the client. "*/
- (void)willBecomeCurrentPreferenceClient;
{
}

/*" Called after the receiver has become the current client and is on screen.  This can be used in cases where you need to know that the UI is visible (necessary to attach child windows, OpenGL contexts, and other things that depend on the controller's window having a window number assigned) and for cases where you need to know that the client's controls have been added to the controller's window. "*/
- (void)didBecomeCurrentPreferenceClient;
{
}

/*" Called when the receiver is about to give up its status as the current client.  This can be used to deregister for notifications used to update the UI for the client. "*/
- (void)resignCurrentPreferenceClient;
{
}

/*" This method should be called whenever a default is changed programmatically.  The default implementation simply calls -updateUI and synchronizes the defaults. "*/
- (void)valuesHaveChanged;
{
    [self updateUI];
}

 // Text delegate methods
 // (We have to be the field's text delegate because otherwise the field will just silently take the value if the user hits tab, and won't set the associated preference.)

/*" The default implementation calls -setValueForSender:, setting the sender to be the notification object (i.e., the text field). "*/
- (void)controlTextDidEndEditing:(NSNotification *)notification;
{
    [self setValueForSender:[notification object]];
}

- (BOOL)wantsAutosizing
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
