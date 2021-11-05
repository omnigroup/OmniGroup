// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPassphrasePrompt.h>

#import <OmniAppKit/OAViewStackConstraints.h>
#import <OmniAppKit/OAStrings.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

OB_REQUIRE_ARC;

@interface OAPassphrasePrompt () <NSTextFieldDelegate>

@property (nonatomic, strong, readwrite) IBOutlet NSTextField *titleField;
@property (nonatomic, strong, readwrite) IBOutlet NSImageView *iconView;

@property (nonatomic) NSTextField *userLabelField;
@property (nonatomic) NSTextField *userNameField;
@property (nonatomic) NSTextField *passwordLabelField;
@property (nonatomic) NSSecureTextField *passwordField;
@property (nonatomic) NSTextField *confirmPasswordLabelField;
@property (nonatomic) NSSecureTextField *confirmPasswordField;
@property (nonatomic) NSButton *rememberInKeychainCheckbox;
@property (nonatomic) IBOutlet NSButton *hintHintField;
@property (nonatomic) IBOutlet NSBox *hintTextBox;
@property (nonatomic) IBOutlet NSTextField *hintTextField;

@property (nonatomic) IBOutlet NSButton *OKButton;
@property (nonatomic) IBOutlet NSButton *cancelButton;
@property (nonatomic) IBOutlet NSButton *auxiliaryButton;

- (IBAction)done:(id)sender;

@end

@implementation OAPassphrasePrompt
{
@private
    BOOL _userEditable;
    NSLayoutGuide *labelBox;
    NSLayoutGuide *fieldsBox;
    OAViewStackConstraints *stacker;
    
    IBOutlet NSTextField *_errorTextField;
}

- (id)initWithOptions:(OAPassphrasePromptOptions)options;
{
    self = [super init];
    if (self == nil)
        return nil;
    
    _minimumPasswordLength = 1;
    _userEditable = (options & OAPassphrasePromptEditableUserField) ? YES : NO;
    
    NSWindow *window = [self window];
    if (window == nil) {
        NSLog(@"Unable to load nib for %@ (%@)", self, [self windowNibName]);
        return nil;
    }
    
    [window setAnchorAttribute:NSLayoutAttributeTop forOrientation:NSLayoutConstraintOrientationVertical];
    window.showsResizeIndicator = YES;
    
    window.accessibilitySubrole = NSAccessibilityDialogSubrole;
    [window setAccessibilityCancelButton:self.cancelButton];
    [window setAccessibilityCloseButton:self.cancelButton];
    self.cancelButton.accessibilitySubrole = NSAccessibilityCloseButtonSubrole;
    [window setAccessibilityDefaultButton:self.OKButton];
    
    self.OKButton.tag = NSModalResponseOK;
    self.cancelButton.tag = NSModalResponseCancel;
    self.auxiliaryButton.tag = NSAlertThirdButtonReturn;
    
    NSView *contentView = window.contentView;
    NSMutableArray *constraints = [NSMutableArray array];

    if (options & OAPassphrasePromptWithoutIcon) {
        // The view's constraints are set up so that removing the icon view from the view hierarchy will only require one horizontal strut to be added to keep things laid out correctly.
        [self.iconView removeFromSuperview];
        self.iconView = nil;
        
        [constraints addObject:[contentView.leadingAnchor constraintEqualToAnchor:self.titleField.leadingAnchor constant:-20]];
    } else {
        self.iconView.accessibilityElement = NO;
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    }
    
    if (!(options & OAPassphrasePromptWithAuxiliaryButton)) {
        [self.auxiliaryButton removeFromSuperview];
        self.auxiliaryButton = nil;
    }
    
    labelBox = [[NSLayoutGuide alloc] init];
    [window.contentView addLayoutGuide:labelBox];
    fieldsBox = [[NSLayoutGuide alloc] init];
    [window.contentView addLayoutGuide:fieldsBox];
    
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSLayoutConstraint *constraint;
    // Horizontal
    [constraints addObject:[labelBox.leadingAnchor constraintEqualToAnchor:self.titleField.leadingAnchor]];
    [constraints addObject:[labelBox.trailingAnchor constraintEqualToAnchor:fieldsBox.leadingAnchor constant:-8.0]];
    constraint = [NSLayoutConstraint constraintWithItem:fieldsBox attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:200];
    constraint.priority = NSLayoutPriorityDefaultLow-1;
    [constraints addObject:constraint];
    [constraints addObject:[fieldsBox.trailingAnchor constraintEqualToAnchor:self.titleField.trailingAnchor]];
    
    // Vertical
    constraint = [fieldsBox.topAnchor constraintEqualToAnchor:self.titleField.bottomAnchor constant:20.0];
    constraint.priority = NSLayoutPriorityRequired;
    [constraints addObject:constraint];
    
    constraint = [fieldsBox.bottomAnchor constraintEqualToAnchor:self.OKButton.topAnchor constant:-20.0];
    constraint.priority = NSLayoutPriorityRequired;
    [constraints addObject:constraint];
    
    NSBundle *bundle = OMNI_BUNDLE;
    NSView *chain = contentView;
    NSMutableArray *stack = [NSMutableArray array];
    
    // According to <bug:///165631>, sometimes the version of this without the default value can return nil. Using this version so we can make sure to return the Key if its not found.
    window.title = NSLocalizedStringWithDefaultValue(@"Passphrase Prompt", @"OmniAppKit", bundle, @"Passphrase Prompt", @"dialog box title - password/passphrase prompt dialog");
    
    self.titleField.maximumNumberOfLines = 0;
    
    // Populate controls based on options
    if (options & OAPassphrasePromptShowUserField) {
        NSTextField *field = [[NSTextField alloc] init];
        [self _stackField:field stack:stack left:YES right:YES];
        
        if (!(options & OAPassphrasePromptEditableUserField)) {
            field.editable = NO;
            field.selectable = NO;
            field.drawsBackground = NO;
            field.bordered = NO;
            [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        } else {
            [chain setNextKeyView:field];
            chain = field;
            field.delegate = self;
        }
        
        self.userNameField = field;

        self.userLabelField = [self addLabel:NSLocalizedStringFromTableInBundle(@"Name:", @"OmniAppKit", bundle, @"field label - password prompt dialog - username or account name")
               toField:field constraints:constraints];
    }
    
    {
        NSSecureTextField *field = [[NSSecureTextField alloc] init];
        [self _stackField:field stack:stack left:YES right:YES];

        [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        
        self.passwordLabelField = [self addLabel:NSLocalizedStringFromTableInBundle(@"Password:", @"OmniAppKit", bundle, @"field label - password prompt dialog - password/passphrase field")
                                         toField:field constraints:constraints];
        
        [chain setNextKeyView:field];
        chain = field;
        field.delegate = self;
        
        self.passwordField = field;
    }
    
    if (options & OAPassphrasePromptConfirmPassword) {
        NSSecureTextField *field = [[NSSecureTextField alloc] init];
        [self _stackField:field stack:stack left:YES right:YES];
        
        [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        self.confirmPasswordLabelField = [self addLabel:NSLocalizedStringFromTableInBundle(@"Confirm:", @"OmniAppKit", bundle, @"field label - password prompt dialog - confirmation of entered password/passphrase")
                                                toField:field constraints:constraints];

        [chain setNextKeyView:field];
        chain = field;
        field.delegate = self;
        
        self.confirmPasswordField = field;
    }
    
    NSButton *reveal = self.hintHintField;
    if (options & OAPassphrasePromptOfferHintText) {
        NSButton *showLabel = self.hintHintField;
        [self _stackField:showLabel stack:stack left:NO right:YES];
        showLabel.showsBorderOnlyWhileMouseInside = YES;
        [self _updateHintLabelForHidden:YES];

        NSBox *hintBox = self.hintTextBox;
        [self _stackField:hintBox stack:stack left:NO right:YES];
        [hintBox setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
        [hintBox setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        hintBox.hidden = YES;

        NSTextField *field = self.hintTextField;
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [field setStringValue:@""];
        field.maximumNumberOfLines = 7;
        field.hidden = YES;
        
        reveal.translatesAutoresizingMaskIntoConstraints = NO;
        [constraints addObject:[reveal.leadingAnchor constraintEqualToAnchor:fieldsBox.leadingAnchor constant:-2.0]];
        
        [chain setNextKeyView:reveal];
        chain = reveal;
    } else {
        [self.hintHintField removeFromSuperview];
        self.hintHintField = nil;
        [self.hintTextField removeFromSuperview];
        self.hintTextField = nil;
        [self.hintTextBox removeFromSuperview];
        self.hintTextBox = nil;
    }
    
    if (options & OAPassphrasePromptShowKeychainOption) {
        NSButton *field = [[NSButton alloc] init];
        [self _stackField:field stack:stack left:YES right:YES];
        [field setButtonType:NSButtonTypeSwitch];
        field.title = NSLocalizedStringFromTableInBundle(@"Remember in Keychain", @"OmniAppKit", bundle, @"checkbox label - password prompt dialog - whether to store this passphrase in the user's keychain");
        [field setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];

        [chain setNextKeyView:field];
        chain = field;

        self.rememberInKeychainCheckbox = field;
    }
    
    {
        [self _stackField:_errorTextField stack:stack left:NO right:YES];
        [constraints addObject:[labelBox.leadingAnchor constraintEqualToAnchor:_errorTextField.leadingAnchor]];
        [_errorTextField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow-1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    
    stacker = [[OAViewStackConstraints alloc] initWithViews:stack between:fieldsBox.topAnchor and:fieldsBox.bottomAnchor axis:NSLayoutConstraintOrientationVertical];
    stacker.firstSpacing = 0;
    stacker.spacing = 8;
    stacker.lastSpacing = 0;
    
    if (self.hintTextBox)
        [stacker constraintFrom:self.hintHintField to:_hintTextBox].constant = 1.0;
    
    [chain setNextKeyView:self.cancelButton];
    
    // Set the localized titles for our controls
    [self.cancelButton setTitle:OACancel()];
    [self.OKButton setTitle:OAOK()];

    [NSLayoutConstraint activateConstraints:constraints];
    [stacker updateViewConstraints];
    [contentView setNeedsLayout:YES];
    
    labelBox = nil;
    fieldsBox = nil;
    
    return self;
}

- (NSString *)windowNibName;
{
    return NSStringFromClass([OAPassphrasePrompt class]);
}

- (NSString *)windowNibPath;
{
    // "Subclasses can override this behavior to augment the search behavior, but probably ought to call super first."
    NSString *path = [super windowNibPath];
    if (path != nil) {
        return path;
    }
    
    path = [[NSBundle bundleForClass:[OAPassphrasePrompt class]] pathForResource:[self windowNibName] ofType:@"nib"];
    return path;
}

- (NSModalResponse)runModal;
{
    [self willShow];

    NSWindow *window = [self window];
    [window makeKeyAndOrderFront:nil];
    
    return [[NSApplication sharedApplication] runModalForWindow:window];
}

- (void)beginSheetModalForWindow:(NSWindow *)parentWindow completionHandler:(void (^)(NSModalResponse returnCode))handler;
{
    OBPRECONDITION(parentWindow != nil);
    OBPRECONDITION(handler != nil);
    handler = [handler copy];
    
    // The first time we show the sheet, there is a flash of white because it hasn't had a chance to draw after applying the layout contraints.
    //
    // TODO Review and file radar.
    
    [self willShow];
    NSWindow *sheetWindow = self.window;
    NSView *contentView = [sheetWindow contentView];
    [contentView updateConstraintsForSubtreeIfNeeded];
    [contentView layoutSubtreeIfNeeded];
    [contentView display];
    
    [parentWindow beginSheet:[self window] completionHandler:^(NSModalResponse returnCode) {
        [sheetWindow orderOut:nil];
        handler(returnCode);
    }];
}

@synthesize usingObfuscatedPasswordPlaceholder = _obscuredPassword;
@synthesize minimumPasswordLength = _minimumPasswordLength;

- (void)setUser:(NSString *)userName;
{
    self.userNameField.stringValue = userName ?: @"";
}

- (NSString *)user;
{
    return self.userNameField.stringValue;
}

- (BOOL)rememberInKeychain;
{
    if (self.rememberInKeychainCheckbox == nil) {
        return NO;
    }
    
    return self.rememberInKeychainCheckbox.state == NSControlStateValueOn;
}

- (void)setRememberInKeychain:(BOOL)rememberInKeychain;
{
    if (!self.rememberInKeychainCheckbox)
        OBRejectInvalidCall(self, _cmd, @"Keychain option not set");

    self.rememberInKeychainCheckbox.state = rememberInKeychain ? NSControlStateValueOn : NSControlStateValueOff;
}

- (NSString *)password;
{
    OBPRECONDITION(self.passwordField != nil);
    
    if (self.usingObfuscatedPasswordPlaceholder)
        return nil;
    
    return self.passwordField.stringValue;
}

- (void)setErrorMessage:(NSString *)errorMessage;
{
    if ([NSString isEmptyString:errorMessage]) {
        _errorTextField.hidden = YES;
        _errorTextField.stringValue = @"";
    } else {
        _errorTextField.stringValue = errorMessage;
        [_errorTextField setPreferredMaxLayoutWidth:self.titleField.frame.size.width];
        [_errorTextField invalidateIntrinsicContentSize];
        [_errorTextField setNeedsUpdateConstraints:YES];
        _errorTextField.hidden = NO;
    }
    
    [stacker updateViewConstraints];
    
    [self.window.contentView setNeedsLayout:YES];
}

- (IBAction)hideShow:(id)sender;
{
    if (!self.hintTextBox.hidden) {
        [self.hintTextField setStringValue: @"" ];
        self.hintTextBox.hidden = YES;
        self.hintTextField.hidden = YES;
    } else {
        [self.hintTextField setStringValue: self.hint ?: @"" ];
        self.hintTextBox.hidden = NO;
        self.hintTextField.hidden = NO;
    }
    [self _updateHintLabelForHidden:self.hintTextField.hidden];
    [self.hintTextField invalidateIntrinsicContentSize];
    [self.hintTextField setNeedsUpdateConstraints:YES];

    [stacker updateViewConstraints];
    [self.window.contentView setNeedsLayout:YES];
}

- (IBAction)done:(id)sender;
{
    NSModalResponse rc = [sender tag];
    
    if (_acceptActionBlock != nil) {
        if (!_acceptActionBlock(self, rc))
            return;
    }
    
    [self endModal:rc];
}

- (void)_stackField:(NSView *)field stack:(NSMutableArray <NSView *> *)stack left:(BOOL)attachLeading right:(BOOL)attachTrailing;
{
    [stack addObject:field];
    if (![field superview])
        [self.window.contentView addSubview:field];
    
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    
    // Horizontal
    if (attachLeading)
        [fieldsBox.leadingAnchor constraintEqualToAnchor:field.leadingAnchor].active = YES;
    
    if (attachTrailing)
        [fieldsBox.trailingAnchor constraintEqualToAnchor:field.trailingAnchor].active = YES;
}

- (NSTextField *)addLabel:(NSString *)localizedLabel toField:(NSControl *)field constraints:(NSMutableArray *)constraints;
{
    NSTextField *label = [[NSTextField alloc] init];
    label.editable = NO;
    label.selectable = NO;
    label.drawsBackground = NO;
    label.bordered = NO;
    label.stringValue = localizedLabel;
    label.alignment = NSTextAlignmentRight;
    
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setContentHuggingPriority:NSLayoutPriorityDragThatCannotResizeWindow+1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    
    [self.window.contentView addSubview:label];
    
    // Horizontal
    [constraints addObject:[NSLayoutConstraint constraintWithItem:labelBox attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:label attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:labelBox attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0]];
    
    // Vertical
    [constraints addObject:[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeBaseline relatedBy:NSLayoutRelationEqual toItem:field attribute:NSLayoutAttributeFirstBaseline multiplier:1.0 constant:0]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationLessThanOrEqual toItem:field attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
    
    label.accessibilityRole = NSAccessibilityStaticTextRole;
    [field setAccessibilityTitleUIElement:label];
    
    return label;
}

#pragma mark NSTextFieldDelegate

- (void)controlTextDidBeginEditing:(NSNotification *)notification;
{
    NSSecureTextField *pw = self.passwordField;

    if (notification.object == pw) {
        if (_obscuredPassword) {
            self.usingObfuscatedPasswordPlaceholder = NO;
        }
    
        NSSecureTextField *confirm = self.confirmPasswordField;
        confirm.enabled = YES;
        confirm.stringValue = @"";
    }
}

- (void)controlTextDidChange:(NSNotification *)notification;
{
    [self _validateActionButtons];
}

#pragma mark Lifecycle

- (void)willShow
{
    NSView *typeHereFirst;
    if (self.userNameField && [NSString isEmptyString:self.userNameField.stringValue]) {
        typeHereFirst = self.userNameField;
    } else if (_obscuredPassword) {
        typeHereFirst = self.OKButton;
    } else {
        typeHereFirst = self.passwordField;
    }
    
    NSWindow *window = self.window;
    [window setInitialFirstResponder:typeHereFirst];
    
    if (_obscuredPassword) {
        self.passwordField.stringValue = OBUnlocalized(@"*****"); // Will show as bullets
        self.confirmPasswordField.enabled = NO;
        self.confirmPasswordField.stringValue = @"";
    } else {
        self.confirmPasswordField.enabled = YES;
    }
    
    [self _validateActionButtons];
}

- (BOOL)isValid;
{
    if (_userEditable && [NSString isEmptyString:self.user]) {
        return NO;
    }
    
    if (_obscuredPassword) {
        // An obscured password is assumed to be valid
    } else {
        if (self.confirmPasswordField != nil && ![[self.confirmPasswordField stringValue] isEqualToString:[self.passwordField stringValue]]) {
            return NO;
        }
        
        if ([self.password length] < _minimumPasswordLength) {
            return NO;
        }
    }
    
    return YES;
}

- (void)endModal:(NSModalResponse)returnCode;
{
    NSWindow *window = [self window];
    if ([window isSheet]) {
        NSWindow *sheetParent = [window sheetParent];
        OBASSERT(sheetParent != nil);
        [sheetParent endSheet:window returnCode:returnCode];
    } else {
        [[NSApplication sharedApplication] stopModalWithCode:returnCode];
        [window orderOut:nil];
    }
}

- (void)_validateActionButtons;
{
    if (_validationBlock != nil) {
        for (NSButton *button in [NSArray arrayWithObjects:self.OKButton, self.auxiliaryButton, nil]) { // Note: self.auxiliaryButton can be nil
            button.enabled = _validationBlock(self, button.tag);
        }
    } else {
        self.OKButton.enabled = self.isValid;
    }
}

- (void)_updateHintLabelForHidden:(BOOL)isCurrentlyHidden;
{
    NSString *hintLabel = isCurrentlyHidden ? NSLocalizedStringFromTableInBundle(@"Show hint…", @"OmniAppKit", OMNI_BUNDLE, @"Show hint label - password/passphrase prompt dialog") : NSLocalizedStringFromTableInBundle(@"Hide hint…", @"OmniAppKit", OMNI_BUNDLE, @"Hide hint label - password/passphrase prompt dialog");
    self.hintHintField.attributedTitle = [[NSAttributedString alloc] initWithString:hintLabel attributes:@{
        NSFontAttributeName: [NSFont labelFontOfSize:[NSFont labelFontSize]],
        NSForegroundColorAttributeName: [NSColor selectedTextColor],
    }];
}

@end
