// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
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

#import <OmniAppKit/OAPreferenceController.h>
#import <OmniAppKit/OAPreferenceClientRecord.h>

RCS_ID("$Id$")

@interface OAPreferenceClient (Private)
- (void)_restoreDefaultsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@implementation OAPreferenceClient

- initWithPreferenceClientRecord:(OAPreferenceClientRecord *)clientRecord controller:(OAPreferenceController *)controller;
{
    NSMutableArray *defaultsArray = [[[[clientRecord defaultsDictionary] allKeys] mutableCopy] autorelease];
    if (!defaultsArray)
        defaultsArray = [NSMutableArray array];
    
    NSArray *recordDefaultsArray = [clientRecord defaultsArray];
    if (recordDefaultsArray)
        [defaultsArray addObjectsFromArray:recordDefaultsArray];
        
    if (![self initWithTitle:[clientRecord title] defaultsArray:defaultsArray controller:controller])
        return nil;
    
    if ([clientRecord nibName] != nil)
        [NSBundle loadNibNamed:[clientRecord nibName] owner:self];

    return self;
}

/*" Creates a new preferences client (with the specified title), which manipulates the specified defaults. "*/
- initWithTitle:(NSString *)newTitle defaultsArray:(NSArray *)newDefaultsArray controller:(OAPreferenceController *)controller;
{
    OBPRECONDITION(![NSString isEmptyString:newTitle]);
    OBPRECONDITION(controller);
    
    _nonretained_controller = controller;
    title = [newTitle copy];
    preferences = [[NSMutableArray alloc] init];
    
    unsigned int defaultIndex, defaultCount = [newDefaultsArray count];
    
    NSString *defaultKeySuffix = [_nonretained_controller defaultKeySuffix];
    NSArray *keys;
    if (![NSString isEmptyString:defaultKeySuffix]) {
        NSMutableArray *clonedKeys = [NSMutableArray array];
        NSMutableDictionary *clonedDefaultRegistration = [NSMutableDictionary dictionaryWithCapacity:defaultCount];
        
        for (defaultIndex = 0; defaultIndex < defaultCount; defaultIndex++) {
            // Register default values for the cloned preferences
            NSString *key = [newDefaultsArray objectAtIndex: defaultIndex];
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
        keys = newDefaultsArray;
    }
    
    for (defaultIndex = 0; defaultIndex < defaultCount; defaultIndex++) {
        NSString *key = [keys objectAtIndex: defaultIndex];
        [self addPreference:[OFPreference preferenceForKey:key]];
    }
    defaults = [[OFPreferenceWrapper sharedPreferenceWrapper] retain];
    
    // Gather the initial values (not in the loop above since subclasses might have done something in -addPreference:)
    NSMutableDictionary *initialValues = [NSMutableDictionary dictionary];
    unsigned int preferenceIndex = [preferences count];
    while (preferenceIndex--) {
	OFPreference *preference = [preferences objectAtIndex:preferenceIndex];
	id value = [preference defaultObjectValue];
	OBASSERT(value); // Avoid raise, but this is really invalid.
	if (value)
	    [initialValues setObject:value forKey:[preference key]];
    }

    // Giving NSUserDefaultsController a wrapper that goes through our OFPreference stuff.  Iffy...
    return [super initWithDefaults:(NSUserDefaults *)defaults initialValues:initialValues];
}

- (void)dealloc;
{
    [controlBox release];
    [initialFirstResponder release];
    [lastKeyView release];
    [title release];
    [preferences release];
    [defaults release];
    [super dealloc];
}

// API

- (void) addPreference: (OFPreference *) preference;
{
    OBPRECONDITION(preference);
#ifdef OMNI_ASSERTIONS_ON
    NSString *suffix = [NSString stringWithFormat:@"-%@", [_nonretained_controller defaultKeySuffix]]; // can't be in the macro invocation or it gets confused by ','
    OBPRECONDITION([NSString isEmptyString:[_nonretained_controller defaultKeySuffix]] || [[preference key] hasSuffix:suffix]);
#endif
    
    if (![preferences containsObjectIdenticalTo: preference]) {
        [preferences addObject: preference];
        [preference setController:self key:@"values"];
    }
}

/*" The controlBox outlet points to the box that will be transferred into the Preferences window when this preference client is selected. "*/
- (NSView *)controlBox;
{
    return controlBox;
}

- (NSView *)initialFirstResponder;
{
    return initialFirstResponder;
}

- (NSView *)lastKeyView;
{
    return lastKeyView;
}

/*" Restores all defaults for this preference client to their original installation values. "*/
- (IBAction)restoreDefaults:(id)sender;
{
    NSString *mainPrompt, *secondaryPrompt, *defaultButton, *otherButton;
    NSBundle *bundle;
    
    bundle = [OAPreferenceClient bundle];
    mainPrompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Reset %@ preferences to their original values?", @"OmniAppKit", bundle, "message text for reset-to-defaults alert"), title];
    secondaryPrompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choosing Reset will restore all settings in this pane to the state they were in when %@ was first installed.", @"OmniAppKit", bundle, "informative text for reset-to-defaults alert"), [[NSProcessInfo processInfo] processName]];
    defaultButton = NSLocalizedStringFromTableInBundle(@"Reset", @"OmniAppKit", bundle, "alert panel button");
    otherButton = NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", bundle, "alert panel button");
    NSBeginAlertSheet(mainPrompt, defaultButton, otherButton, nil, [controlBox window], self, NULL, @selector(_restoreDefaultsSheetDidEnd:returnCode:contextInfo:), NULL, secondaryPrompt);
}

- (void)restoreDefaultsNoPrompt;
{
    [self revertToInitialValues:nil];
    OBPOSTCONDITION([self haveAnyDefaultsChanged] == NO);
}

- (BOOL)haveAnyDefaultsChanged;
{
    unsigned int preferenceIndex = [preferences count];
    while (preferenceIndex--) {
        OFPreference *aPreference = [preferences objectAtIndex:preferenceIndex];
        if ([aPreference hasNonDefaultValue]) {
#ifdef DEBUG_kc0
            NSLog(@"-%s: non-default value: '%@' = '%@'", _cmd, [aPreference key], [aPreference objectValue]);
#endif
            return YES;
        }
    }

    return [self hasUnappliedChanges]; // Checks if there are editors active
}

/*" Prompts the user for a directory (using an open panel), then updates the text field to display it and calls -setValueForSender: specifying that field as the sender. "*/
- (void)pickDirectoryForTextField:(NSTextField *)textField;
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseDirectories:YES];
    if ([openPanel runModalForTypes:nil] != NSOKButton)
	return;
    
    NSString *directory = [[openPanel filenames] objectAtIndex: 0];
    [textField setStringValue:directory];
    [self setValueForSender:textField];
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
    [textField setIntValue:[preference integerValue]];
    NSBeep();
}


// Subclass me!

/*" Updates the UI to reflect the current defaults. "*/
- (void)updateUI;
{
}

/*" Updates defaults for a modified UI element (the sender). "*/
- (void)setValueForSender:(id)sender;
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
    [defaults autoSynchronize];
}

 // Text delegate methods
 // (We have to be the field's text delegate because otherwise the field will just silently take the value if the user hits tab, and won't set the associated preference.)

/*" The default implementation calls -setValueForSender:, setting the sender to be the notification object (i.e., the text field). "*/
- (void)controlTextDidEndEditing:(NSNotification *)notification;
{
    [self setValueForSender:[notification object]];
}


// NSNibAwaking informal protocol

/*" Be sure to call super if you subclass this "*/
- (void)awakeFromNib;
{
    [controlBox retain];
}

@end

@implementation OAPreferenceClient (Private)

- (void)_restoreDefaultsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode != NSAlertDefaultReturn)
        return;
    [self restoreDefaultsNoPrompt];
    [self valuesHaveChanged];
}

@end
