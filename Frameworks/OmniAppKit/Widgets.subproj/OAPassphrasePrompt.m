// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPassphrasePrompt.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

OB_REQUIRE_ARC;

@interface OAPassphrasePrompt () <NSTextFieldDelegate>

@property (nonatomic, strong, readwrite) IBOutlet NSTextField *titleField;
@property (nonatomic, strong, readwrite) IBOutlet NSImageView *iconView;

@property (nonatomic) NSTextField *userNameField;
@property (nonatomic) NSSecureTextField *passwordField;
@property (nonatomic) NSSecureTextField *confirmPasswordField;
@property (nonatomic) NSButton *rememberInKeychainCheckbox;

@property (nonatomic) IBOutlet NSButton *OKButton;
@property (nonatomic) IBOutlet NSButton *cancelButton;

- (IBAction)done:(id)sender;

@end

@implementation OAPassphrasePrompt
{
@private
    BOOL _userEditable;
    NSLayoutGuide *labelBox;
    NSLayoutGuide *fieldsBox;
    NSLayoutAnchor *lastAnchor;
    
    NSLayoutConstraint *visibleErrorConstraint, *invisibleErrorConstraint;
    
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
    
    self.iconView.accessibilityElement = NO;
    
    NSMutableArray *constraints = [NSMutableArray array];

    labelBox = [[NSLayoutGuide alloc] init];
    [window.contentView addLayoutGuide:labelBox];
    fieldsBox = [[NSLayoutGuide alloc] init];
    [window.contentView addLayoutGuide:fieldsBox];
    lastAnchor = nil;
    
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSLayoutConstraint *constraint;
    // Horizontal
    [constraints addObject:[labelBox.leadingAnchor constraintEqualToAnchor:self.titleField.leadingAnchor]];
    [constraints addObject:[NSLayoutConstraint constraintWithItem:labelBox attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:fieldsBox attribute:NSLayoutAttributeLeading multiplier:1.0 constant:-8.0]];
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
    invisibleErrorConstraint = constraint;
    
    {
        NSLayoutConstraint *above = [fieldsBox.bottomAnchor constraintEqualToAnchor:_errorTextField.topAnchor constant:-8.0];
        NSLayoutConstraint *below = [_errorTextField.bottomAnchor constraintEqualToAnchor:self.OKButton.topAnchor constant:-20.0];
        NSLayoutConstraint *leadn = [labelBox.leadingAnchor constraintEqualToAnchor:_errorTextField.leadingAnchor];
        NSLayoutConstraint *trail = [fieldsBox.trailingAnchor constraintEqualToAnchor:_errorTextField.trailingAnchor];
        
        above.priority = NSLayoutPriorityRequired;
        below.priority = NSLayoutPriorityRequired;
        [constraints addObject:below];
        [constraints addObject:leadn];
        [constraints addObject:trail];
        
        visibleErrorConstraint = above;
        
        [_errorTextField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow-1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_errorTextField setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        _errorTextField.translatesAutoresizingMaskIntoConstraints = NO;
    }
    
    NSBundle *bundle = [OAPassphrasePrompt bundle];
    NSView *chain = window.contentView;
    
    window.title = NSLocalizedStringFromTableInBundle(@"Passphrase Prompt", @"OmniAppKit", bundle, @"dialog box title - password/passphrase prompt dialog");
    
    // Populate controls based on options
    if (options & OAPassphrasePromptShowUserField) {
        NSTextField *field = [[NSTextField alloc] init];
        
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
        
        [self addField:field
              andLabel:NSLocalizedStringFromTableInBundle(@"Name:", @"OmniAppKit", bundle, @"field label - password prompt dialog - username or account name")
           constraints:constraints property:@"userLabelField"];
        OBASSERT(self.userLabelField != nil);
        
        self.userNameField = field;
    }
    
    {
        NSSecureTextField *field = [[NSSecureTextField alloc] init];
        [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addField:field
              andLabel:NSLocalizedStringFromTableInBundle(@"Password:", @"OmniAppKit", bundle, @"field label - password prompt dialog - password/passphrase field")
           constraints:constraints property:nil];

        [chain setNextKeyView:field];
        chain = field;
        field.delegate = self;
        
        self.passwordField = field;
    }
    
    if (options & OAPassphrasePromptConfirmPassword) {
        NSSecureTextField *field = [[NSSecureTextField alloc] init];
        [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addField:field
              andLabel:NSLocalizedStringFromTableInBundle(@"Confirm:", @"OmniAppKit", bundle, @"field label - password prompt dialog - confirmation of entered password/passphrase")
           constraints:constraints property:nil];

        [chain setNextKeyView:field];
        chain = field;
        field.delegate = self;
        
        self.confirmPasswordField = field;
    }
    
    if (options & OAPassphrasePromptShowKeychainOption) {
        NSButton *field = [[NSButton alloc] init];
        [field setButtonType:NSSwitchButton];
        field.title = NSLocalizedStringFromTableInBundle(@"Remember in Keychain", @"OmniAppKit", bundle, @"checkbox label - password prompt dialog - whether to store this passphrase in the user's keychain");
        [field setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        [self addField:field andLabel:nil constraints:constraints property:nil];

        [chain setNextKeyView:field];
        chain = field;

        self.rememberInKeychainCheckbox = field;
    }
    
    // TODO: Password hint box
    
    [constraints addObject:[lastAnchor constraintEqualToAnchor:fieldsBox.bottomAnchor]];
    
    [chain setNextKeyView:self.cancelButton];
    
    // Set the localized titles for our controls
    [self.cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", bundle, @"button title - password prompt dialog")];
    [self.OKButton setTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniAppKit", bundle, @"button title - password prompt dialog")];

    [NSLayoutConstraint activateConstraints:constraints];
    [window.contentView setNeedsLayout:YES];
    
    labelBox = nil;
    fieldsBox = nil;
    lastAnchor = nil;
        
    return self;
}

- (NSString *)windowNibName;
{
    return NSStringFromClass([self class]);
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
    
    return self.rememberInKeychainCheckbox.state == NSOnState;
}

- (void)setRememberInKeychain:(BOOL)rememberInKeychain;
{
    if (!self.rememberInKeychainCheckbox)
        OBRejectInvalidCall(self, _cmd, @"Keychain option not set");

    self.rememberInKeychainCheckbox.state = rememberInKeychain ? NSOnState : NSOffState;
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
    BOOL isHidden = _errorTextField.hidden;
    
    if ([NSString isEmptyString:errorMessage]) {
        if (!isHidden) {
            _errorTextField.hidden = YES;
            visibleErrorConstraint.active = NO;
            invisibleErrorConstraint.active = YES;
        }
        _errorTextField.stringValue = @"";
    } else {
        _errorTextField.stringValue = errorMessage;
        [_errorTextField setPreferredMaxLayoutWidth:self.titleField.frame.size.width];
        [_errorTextField invalidateIntrinsicContentSize];
        [_errorTextField setNeedsUpdateConstraints:YES];
        if (isHidden) {
            invisibleErrorConstraint.active = NO;
            visibleErrorConstraint.active = YES;
            _errorTextField.hidden = NO;
        }
    }
    
    [self.window.contentView setNeedsLayout:YES];
}

- (IBAction)done:(id)sender;
{
    NSModalResponse rc = ( [sender tag] == 0 ) ? NSModalResponseCancel : NSModalResponseOK;
    [self endModal:rc];
}

- (void)addField:(NSControl *)field andLabel:(NSString *)localizedLabel constraints:(NSMutableArray *)constraints property:(NSString *)propertyName;
{
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSView *contentView = self.window.contentView;
    [contentView addSubview:field];

    // Horizontal
    [constraints addObject:[fieldsBox.leadingAnchor constraintEqualToAnchor:field.leadingAnchor]];
    [constraints addObject:[fieldsBox.trailingAnchor constraintEqualToAnchor:field.trailingAnchor]];
    
    // Vertical
    NSLayoutConstraint *constraint;
    if (lastAnchor) {
        constraint = [field.topAnchor constraintEqualToAnchor:lastAnchor constant:8];
    } else {
        constraint = [field.topAnchor constraintEqualToAnchor:fieldsBox.topAnchor];
    }
    constraint.priority = NSLayoutPriorityRequired;
    [constraints addObject:constraint];
    lastAnchor = field.bottomAnchor;

    if (localizedLabel) {
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
        
        [contentView addSubview:label];
        if (propertyName)
            [self setValue:label forKey:propertyName];
        
        // Horizontal
        [constraints addObject:[NSLayoutConstraint constraintWithItem:labelBox attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:label attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0]];
        [constraints addObject:[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:labelBox attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0]];
        
        // Vertical
        [constraints addObject:[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeBaseline relatedBy:NSLayoutRelationEqual toItem:field attribute:NSLayoutAttributeFirstBaseline multiplier:1.0 constant:0]];
        [constraints addObject:[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationLessThanOrEqual toItem:field attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
        
        label.accessibilityRole = NSAccessibilityStaticTextRole;
        [field setAccessibilityTitleUIElement:label];
    }
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
    self.OKButton.enabled = [self isValid];
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
        self.passwordField.stringValue = @"*****"; // Will show as bullets
        self.confirmPasswordField.enabled = NO;
        self.confirmPasswordField.stringValue = @"";
    } else {
        self.confirmPasswordField.enabled = YES;
    }
    
    self.OKButton.enabled = [self isValid];
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

@end
