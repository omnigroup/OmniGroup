// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentNavigationItem.h>

#import <OmniUIDocument/OUIDocumentTitleView.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXAccountActivity.h>
#import <OmniFileExchange/OFXAgentActivity.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIRotationLock.h>
#import <OmniUI/OUIShieldView.h>
#import <OmniUI/OUIInteractionLock.h>
#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentAppController.h>

#import "OUIFullWidthNavigationItemTitleView.h"

#if 0 && defined(DEBUG)
#define DEBUG_EDIT_MODE(format, ...) NSLog(@"EDIT_MODE: " format, ## __VA_ARGS__)
#else
#define DEBUG_EDIT_MODE(format, ...)
#endif

NSString * const OUIDocumentNavigationItemNewDocumentNameUserInfoKey = @"OUIDocumentNavigationItemNewDocumentNameUserInfoKey";
NSString * const OUIDocumentNavigationItemOriginalDocumentNameUserInfoKey = @"OUIDocumentNavigationItemOriginalDocumentNameUserInfoKey";


@interface OUIDocumentNavigationItem () <UITextFieldDelegate, OUIDocumentTitleViewDelegate>

@property (nonatomic, weak, readwrite) OUIDocument *document;
@property (nonatomic, strong) OUIDocumentTitleView *documentTitleView;
@property (nonatomic, strong) OUIShieldView *shieldView;

@property (nonatomic, strong) UIView *documentTitleTextFieldView;
@property (nonatomic, strong) UITextField *documentTitleTextField;

@property (nonatomic, strong) NSArray *usersLeftBarButtonItems;
@property (nonatomic, strong) NSArray *usersRightBarButtonItems;

@property (nonatomic, strong) OUIRotationLock *renamingRotationLock;

@property (nonatomic, copy) NSString *observedDocumentName;

@end

@implementation OUIDocumentNavigationItem
{
    OFBinding *_fileNameBinding;
    
    BOOL _hasAttemptedRename;
    BOOL _renaming;
}

- (instancetype)initWithDocument:(OUIDocument *)document;
{
    // We do want to make sure our title property stays up to date with the document's title, so that if another view controller is pushed on to the navigation stack after us, the right name appears in the Back button.
    NSString *title = document.name;
    
    _titleColor = [UIColor labelColor];
    
    self = [super initWithTitle:title];
    if (self) {
        _document = document;
        
        _documentTitleView = [[OUIDocumentTitleView alloc] init];
        _documentTitleView.title = title;
        _documentTitleView.delegate = self;
        _documentTitleView.hideTitle = NO;
                
        OFXServerAccount *account = [OFXServerAccount accountSyncingLocalURL:document.fileURL fromRegistry:OFXServerAccountRegistry.defaultAccountRegistry];
        if (account != nil) {
            OFXAgentActivity *agentActivity = [OUIDocumentAppController controller].agentActivity;
            _documentTitleView.syncAccountActivity = [agentActivity activityForAccount:account];
            OBASSERT(_documentTitleView.syncAccountActivity != nil);
        }

        _documentTitleView.titleCanBeTapped = document.canRename;
        self.title = title;
        
        self.titleView = _documentTitleView;

        // Bind to a separate property since the document `name` will change on a file presenter's background queue.
        _observedDocumentName = [title copy];
        _fileNameBinding = [[OFBinding alloc] initWithSourceObject:document sourceKeyPath:OFValidateKeyPath(document, name) destinationObject:self destinationKeyPath:OFValidateKeyPath(self, observedDocumentName)]; // value already propagated by designated initializer
        
        _documentTitleTextField = [[UITextField alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 200.0f, 31.0f)];
        _documentTitleTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _documentTitleTextField.font = [UIFont boldSystemFontOfSize:17.0f];
        _documentTitleTextField.textAlignment = NSTextAlignmentCenter;
        _documentTitleTextField.autocapitalizationType = UITextAutocapitalizationTypeWords;
        _documentTitleTextField.borderStyle = UITextBorderStyleNone;
        _documentTitleTextField.textColor = _titleColor;
        _documentTitleTextField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _documentTitleTextField.delegate = self;
        
        // Custom clear button.
        _documentTitleTextField.clearButtonMode = UITextFieldViewModeNever;
        UIImage *clearButtonImage = [[UIImage imageNamed:@"OUITextField-ClearButton" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIButton *customClearButton = [UIButton buttonWithType:UIButtonTypeCustom];
        customClearButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Clear Title", @"OmniUIDocument", OMNI_BUNDLE, @"title view clear button accessibility label.");
        
        customClearButton.frame = (CGRect){
            .size.width = 31.0f,
            .size.height = 31.0f
        };
        [customClearButton addTarget:self action:@selector(_clearDocumentTitleTextField:) forControlEvents:UIControlEventTouchUpInside];
        [customClearButton setImage:clearButtonImage forState:UIControlStateNormal];
        _documentTitleTextField.rightView = customClearButton;
        _documentTitleTextField.rightViewMode = UITextFieldViewModeAlways;


        // Keep text centered by evening out the padding on the left.
        UIView *leftView = [[UIView alloc] init];
        CGRect clearButtonRect = _documentTitleTextField.rightView.frame;
        
        CGRect leftViewFrame = (CGRect){
            .origin = CGPointZero,
            .size.width = clearButtonRect.size.width,
            .size.height = 6.0f // Just some height so it can be seen in debug when using a background color.
        };
        
        leftView.frame = leftViewFrame;
        _documentTitleTextField.leftView = leftView;
        _documentTitleTextField.leftViewMode = UITextFieldViewModeAlways;
        
        _documentTitleTextFieldView = [[OUIFullWidthNavigationItemTitleView alloc] initWithFrame:_documentTitleTextField.bounds];
        [_documentTitleTextFieldView addSubview:_documentTitleTextField];
    }
    return self;
}

- (void)dealloc;
{
    self.usersLeftBarButtonItems = nil;
    self.usersRightBarButtonItems = nil;
    self.renaming = NO;
    [_fileNameBinding invalidate];
    _documentTitleView.delegate = nil;
}

- (void)documentWillClose;
{
    [_fileNameBinding invalidate];
    _fileNameBinding = nil;
}

- (BOOL)hideTitle;
{
    return [self.title isEqualToString:@""];
}

- (void)setHideTitle:(BOOL)hideTitle;
{
    if (hideTitle) {
        self.title = @"";
        _documentTitleView.titleCanBeTapped = NO;
    } else {
        self.title = self.document.name;
        _documentTitleView.titleCanBeTapped = YES;
    }
}

/*!
 * @brief Sets both the navigation item's title (for use in a back button) and the title visable to the user in our custom documentTitleView.
 */
- (void)setTitle:(NSString *)title;
{
    [super setTitle:title];
    _documentTitleView.title = title;
}

// We allow overriding the title temporarily (while in Edit mode on the toolbar, for example, to display instructional text). When the titleView is set back to nil we use our normal rename UI.
- (void)setTitleView:(UIView *)titleView;
{
    if (!titleView) {
        if (_renaming)
            titleView = _documentTitleTextFieldView;
        else
            titleView = _documentTitleView;
    }
    [super setTitleView:titleView];
}

- (BOOL)endRenaming;
{
    if (!_renaming) {
        OBASSERT(self.shieldView == nil);
        return YES;
    }

    return [_documentTitleTextField resignFirstResponder];
}

- (void)setTitleColor:(UIColor *)titleColor;
{
    if (OFISEQUAL(_titleColor, titleColor))
        return;
    
    _titleColor = titleColor;
    _documentTitleView.titleColor = titleColor;
    _documentTitleTextField.textColor = titleColor;
}

- (void)setObservedDocumentName:(NSString *)observedDocumentName;
{
    // We used to assert that this would only be called on a background thread, but on iOS 13 our Document.name binding gets called on the main thread as well

    _observedDocumentName = [observedDocumentName copy];
    
    __weak OUIDocumentNavigationItem *weakSelf = self;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        OUIDocumentNavigationItem *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.title = observedDocumentName;
    }];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    OBPRECONDITION(_hasAttemptedRename == NO);
    
    OUIDocument *document = _document;
    [document willEditDocumentTitle];
    textField.keyboardAppearance = [OUIAppController controller].defaultKeyboardAppearance;
    
    textField.text = document.editingName;
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
{
    // If we are new, there will be no fileItem.
    // Actually, we give documents default names and load their fileItem up immediately on creation...
    OUIDocument *document = _document;
    NSString *originalName = document.editingName;
    OBASSERT(originalName);
    
    NSString *newName = [textField text];
    if (_hasAttemptedRename || [NSString isEmptyString:newName] || [newName isEqualToString:originalName] || document.editingDisabled) {
        _hasAttemptedRename = NO; // This rename finished (or we are going to discard it due to an incoming iCloud edit); prepare for the next one.
        textField.text = originalName;
        return YES;
    }
    
    // Otherwise, start the rename and return NO for now, but remember that we've tried already.
    _hasAttemptedRename = YES;

#ifdef OMNI_ASSERTIONS_ON
    NSURL *currentURL = [document.fileURL copy];
    NSString *uti = OFUTIForFileExtensionPreferringNative([currentURL pathExtension], nil);
    OBASSERT(uti);
#endif

    self.title = newName; // edit field will be dismissed and the title label displayed before the rename is completed so this will make sure that the label shows the updated name
    
    [document renameToName:newName completionBlock:^(BOOL success, NSError *error) {
        if (!success) {
            [error log:@"Error renaming document with URL \"%@\" to \"%@\"", document.fileURL.absoluteString, newName];
            OUI_PRESENT_ERROR_IN_SCENE(error, _documentTitleTextField.window.windowScene);

            self.title = originalName;

            if (NO /* [error hasUnderlyingErrorDomain:ODSErrorDomain code:ODSFilenameAlreadyInUse] */) {
                // Leave the fixed name for the user to try again.
                _hasAttemptedRename = NO;
            } else {
                // Some other error which may not be correctable -- bail
                [_documentTitleTextField endEditing:YES];
            }
        } else {
            // Don't need to scroll the document picker in this copy of the code.
            [_documentTitleTextField endEditing:YES];
        }
    }];

    return NO; // Don't end editing until we succeed
}

- (void)setRenaming:(BOOL)isRenaming;
{
    if (_renaming == isRenaming)
        return;

    _renaming = isRenaming;
    [self _updateItemsForRenaming];
}

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    self.renaming = NO;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    // <bug:///61021> (If you add a forward slash "/" to the document title, it will revert to the old title upon saving)
    NSRange r = [string rangeOfString:@"/"];
    if (r.location != NSNotFound) {
        return NO;
    }

    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);

    if (_documentTitleTextField.isEditing)
        [_documentTitleTextField endEditing:YES];
    
    return YES;
}

#pragma mark - OUIDocumentTitleViewDelegate

- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView titleTapped:(id)sender;
{
    if (_renaming) {
        return;
    }

    self.renaming = YES;
}

#pragma mark - Helpers

- (void)_finishUpdateItemsForRenaming;
{
    // Prevent rotation while in rename mode.
    self.renamingRotationLock = [OUIRotationLock rotationLock];

    // Make sure we're prepared to switch into rename mode.
    OBASSERT(self.usersLeftBarButtonItems == nil);
    OBASSERT(self.usersRightBarButtonItems == nil);

    // Cache user's items.
    self.usersLeftBarButtonItems = self.leftBarButtonItems;
    self.usersRightBarButtonItems = self.rightBarButtonItems;

    // Remove user's item.
    self.leftBarButtonItems = nil;
    self.rightBarButtonItems = nil;

    // Set our textField as the titleView and give it focus.
    self.titleView = _documentTitleTextFieldView;
    _documentTitleTextField.returnKeyType = UIReturnKeyDone;
    [_documentTitleTextField becomeFirstResponder];

    // Add Shield View
    UIWindow *window = self.document.documentViewController.view.window;
    UITapGestureRecognizer *shieldViewTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_shieldViewTapped:)];
    NSArray *passthroughViews = [NSArray arrayWithObject:_documentTitleTextField];
    OUIShieldView *shieldView = [OUIShieldView shieldViewWithView:window];
    [shieldView addGestureRecognizer:shieldViewTapRecognizer];
    shieldView.passthroughViews = passthroughViews;
    self.shieldView = shieldView;
    [window addSubview:shieldView];
    [window bringSubviewToFront:shieldView];
}

- (void)_updateItemsForRenaming;
{
    if (_renaming) {
        DEBUG_EDIT_MODE(@"Switching to rename mode.");
        // only save the document if there are changes
        OUIDocument *document = self.document;
        if (document.hasUnsavedChanges) {
            [document saveToURL:document.fileURL forSaveOperation:UIDocumentSaveForOverwriting completionHandler:^(BOOL success) {
                [self _finishUpdateItemsForRenaming];
            }];
        } else {
            [self _finishUpdateItemsForRenaming];
        }
        
    }
    else {
        DEBUG_EDIT_MODE(@"Switching to non-rename mode.");
        
        // Allow rotation again.
        [_renamingRotationLock unlock];
        _renamingRotationLock = nil;
        
        // Add user's items back.
        if (_usersLeftBarButtonItems != nil) {
            self.leftBarButtonItems = _usersLeftBarButtonItems;
            _usersLeftBarButtonItems = nil;
        }
        if (_usersRightBarButtonItems != nil) {
            self.rightBarButtonItems = _usersRightBarButtonItems;
            _usersRightBarButtonItems = nil;
        }
        
        // Set our titleView back.
        self.titleView = _documentTitleView;
        
        // Remove Shield View
        if (_shieldView) {
            [_shieldView removeFromSuperview];
            _shieldView = nil;
        }
    }
}

- (void)_shieldViewTapped:(UIGestureRecognizer *)gestureRecognizer;
{
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self endRenaming];
    }
}

- (void)_clearDocumentTitleTextField:(id)sender;
{
    _documentTitleTextField.text = nil;
}

@end
