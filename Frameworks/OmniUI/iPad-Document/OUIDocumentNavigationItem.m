// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentNavigationItem.h>

#import <OmniUIDocument/OUIDocumentTitleView.h>
#import <OmniDocumentStore/ODSErrors.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniFileExchange/OFXAccountActivity.h>
#import <OmniFileExchange/OFXAgentActivity.h>
#import <OmniFileExchange/OFXDocumentStoreScope.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUI/OUIRotationLock.h>
#import <OmniUI/OUIShieldView.h>
#import <OmniUI/OUIInteractionLock.h>
#import <OmniUIDocument/OUIDocumentAppController.h>

#import "OUIDocument-Internal.h"
#import "OUIFullWidthNavigationItemTitleView.h"

RCS_ID("$Id$");

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
    ODSFileItem *fileItem = document.fileItem;
    NSString *title = fileItem.name;
    
    _titleColor = [UIColor blackColor];
    
    self = [super initWithTitle:title];
    if (self) {
        _document = document;
        
        _documentTitleView = [[OUIDocumentTitleView alloc] init];
        _documentTitleView.title = title;
        _documentTitleView.delegate = self;
        _documentTitleView.hideTitle = NO;
        
        if ([fileItem.scope isKindOfClass:[OFXDocumentStoreScope class]]) {
            OFXDocumentStoreScope *scope = (OFXDocumentStoreScope *)fileItem.scope;
            OFXAgentActivity *agentActivity = [OUIDocumentAppController controller].agentActivity;
            _documentTitleView.syncAccountActivity = [agentActivity activityForAccount:scope.account];
            OBASSERT(_documentTitleView.syncAccountActivity != nil);
        }
        
        _documentTitleView.titleCanBeTapped = fileItem.scope.canRenameDocuments;
        self.title = title;
        
        self.titleView = _documentTitleView;

        _fileNameBinding = [[OFBinding alloc] initWithSourceObject:fileItem sourceKeyPath:OFValidateKeyPath(fileItem, name) destinationObject:self destinationKeyPath:OFValidateKeyPath(self, title)]; // value already propagated by designated initializer
        
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
    [_fileNameBinding invalidate];
    _documentTitleView.delegate = nil;
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
        self.title = self.document.fileItem.name;
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

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    OBPRECONDITION(_hasAttemptedRename == NO);
    
    [_document willEditDocumentTitle];
    textField.keyboardAppearance = [OUIAppController controller].defaultKeyboardAppearance;

    ODSFileItem *fileItem = _document.fileItem;
    OBASSERT(fileItem);
    
    textField.text = fileItem.editingName;
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
{
    // If we are new, there will be no fileItem.
    // Actually, we give documents default names and load their fileItem up immediately on creation...
    ODSFileItem *fileItem = _document.fileItem;
    NSString *originalName = fileItem.editingName;
    OBASSERT(originalName);
    
    NSString *newName = [textField text];
    if (_hasAttemptedRename || [NSString isEmptyString:newName] || [newName isEqualToString:originalName] || _document.editingDisabled) {
        _hasAttemptedRename = NO; // This rename finished (or we are going to discard it due to an incoming iCloud edit); prepare for the next one.
        textField.text = originalName;
        return YES;
    }
    
    // Otherwise, start the rename and return NO for now, but remember that we've tried already.
    _hasAttemptedRename = YES;
    NSURL *currentURL = [fileItem.fileURL copy];
    
    NSString *uti = OFUTIForFileExtensionPreferringNative([currentURL pathExtension], nil);
    OBASSERT(uti);
    
    // We don't want a "directory changed" notification for the local documents directory.
//    OUIDocumentPicker *documentPicker = self.documentPicker;
    
    // Tell the document that the rename is local
    [_document _willBeRenamedLocally];
    self.title = newName; // edit field will be dismissed and the title label displayed before the rename is completed so this will make sure that the label shows the updated name
    
    // Make sure we don't close the document while the rename is happening, or some such. It would probably be OK with the synchronization API, but there is no reason to allow it.
    OUIInteractionLock *lock = [OUIInteractionLock applicationLock];
    
    [fileItem.scope renameFileItem:fileItem baseName:newName fileType:uti completionHandler:^(NSURL *destinationURL, NSError *error){
        main_async(^{
            
            [lock unlock];
            
            if (!destinationURL) {
                NSLog(@"Error renaming document with URL \"%@\" to \"%@\" with type \"%@\": %@", [currentURL absoluteString], newName, uti, [error toPropertyList]);
                OUI_PRESENT_ERROR(error);

                self.title = originalName;
                
                if ([error hasUnderlyingErrorDomain:ODSErrorDomain code:ODSFilenameAlreadyInUse]) {
                    // Leave the fixed name for the user to try again.
                    _hasAttemptedRename = NO;
                } else {
                    // Some other error which may not be correctable -- bail
                    [_documentTitleTextField endEditing:YES];
                }
            } else {
                // Don't need to scroll the document picker in this copy of the code.
                //[documentPicker _didPerformRenameToFileURL:destinationURL];
                [_documentTitleTextField endEditing:YES];
            }
        });
    }];
    
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    _renaming = NO;
    [self _updateItemsForRenaming];
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

- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView syncButtonTapped:(id)sender;
{
    [_document _manualSync:sender];
}

- (void)documentTitleView:(OUIDocumentTitleView *)documentTitleView titleTapped:(id)sender;
{
    if (_renaming) {
        return;
    }
    
    _renaming = YES;
    [self _updateItemsForRenaming];
}

#pragma mark - Helpers

- (void)_updateItemsForRenaming;
{
    if (_renaming) {
        DEBUG_EDIT_MODE(@"Switching to rename mode.");
        // save the document
        [self.document saveToURL:self.document.fileURL forSaveOperation:UIDocumentSaveForOverwriting completionHandler:^(BOOL success) {           
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
            
            // Add Shild View
            UIWindow *window = [OUIAppController controller].window;
            UITapGestureRecognizer *shieldViewTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_shieldViewTapped:)];
            NSArray *passthroughViews = [NSArray arrayWithObject:_documentTitleTextField];
            self.shieldView = [OUIShieldView shieldViewWithView:window];
            [self.shieldView addGestureRecognizer:shieldViewTapRecognizer];
            self.shieldView.passthroughViews = passthroughViews;
            [window addSubview:self.shieldView];
            [window bringSubviewToFront:self.shieldView];
        }];
        
    }
    else {
        DEBUG_EDIT_MODE(@"Switching to non-rename mode.");
        
        // Allow rotation again.
        [self.renamingRotationLock unlock];
        self.renamingRotationLock = nil;
        
        // Can't make these assertions becuase these items may have never been set.
        //        OBASSERT(self.usersLeftBarButtonItems);
        //        OBASSERT(self.usersRightBarButtonItems);
        
        // Add user's items back.
        self.leftBarButtonItems = self.usersLeftBarButtonItems;
        self.rightBarButtonItems = self.usersRightBarButtonItems;
        
        // Clear cached user's items.
        self.usersLeftBarButtonItems = nil;
        self.usersRightBarButtonItems = nil;
        
        // Set our titleView back.
        self.titleView = _documentTitleView;
        
        // Remove Shield View
        if (self.shieldView) {
            [self.shieldView removeFromSuperview];
            self.shieldView = nil;
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
