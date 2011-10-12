// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentRenameViewController.h"

#import <OmniFileStore/OFSFileInfo.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniUI/OUIAnimationSequence.h>
#import <OmniUI/OUIDocumentPickerDelegate.h>
#import <OmniUI/OUIDocumentPickerFileItemView.h>
#import <OmniUI/OUIDocumentPickerFileItemView.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUIDocumentPreviewView.h>
#import <OmniUI/OUIDocumentStore.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/OUISingleDocumentAppController.h>
#import <OmniUI/OUIMainViewController.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define RENAME_DEBUG(format, ...) NSLog(@"RENAME: " format, ## __VA_ARGS__)
#else
    #define RENAME_DEBUG(format, ...)
#endif

@interface OUIDocumentRenameViewController () <UITextFieldDelegate, NSFilePresenter>
- (void)_cancel;
- (void)_done:(id)sender;
- (void)_startRenameStateChange:(BOOL)renaming withDuration:(NSTimeInterval)animationInterval curve:(UIViewAnimationCurve)animationCurve;
- (void)_finishRenameAfterHidingKeyboard;
- (void)_resizeForKeyboard:(NSNotification *)note;
- (void)_keyboardDidHide:(NSNotification *)note;
@end

@implementation OUIDocumentRenameViewController
{
    OUIDocumentPicker *_picker;
    OUIDocumentStoreFileItem *_fileItem;
    
    NSOperationQueue *_filePresenterQueue;
    NSURL *_presentedFileURL; // Remember the original file URL in case there is an incoming rename; we want to be able to respond to NSFilePresenter -presentedItemURL correctly in this case.
    
    BOOL _isRegisteredAsFilePresenter;
    BOOL _keyboardVisible;
    BOOL _registeredForNotifications;
    BOOL _renameStarted;
    OUIDocumentPreviewView *_previewView;
    UITextField *_nameTextField;
}

- initWithDocumentPicker:(OUIDocumentPicker *)picker fileItem:(OUIDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(picker);
    OBPRECONDITION(fileItem);
    OBPRECONDITION([picker.documentStore.fileItems member:fileItem] == fileItem);
    
    if (!(self = [super init]))
        return nil;
    
    _picker = [picker retain];
    _fileItem = [fileItem retain];
    
    _presentedFileURL = [_fileItem.fileURL copy];
    _filePresenterQueue = [[NSOperationQueue alloc] init];
    _filePresenterQueue.name = @"OUIDocumentRenameViewController NSFilePresenter notifications";
    _filePresenterQueue.maxConcurrentOperationCount = 1;
    
    // This will retain us, so we cannot -removeFilePresenter: in dealloc.
    [NSFileCoordinator addFilePresenter:self];
    _isRegisteredAsFilePresenter = YES;
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_picker release];
    [_fileItem release];
    
    [_presentedFileURL release];
    [_filePresenterQueue release];
    
    [_previewView release];
    [_nameTextField release];
    
    [super dealloc];
}

- (void)startRenaming;
{
    OBPRECONDITION(_renameStarted == NO);
    
    RENAME_DEBUG(@"Starting");
    
    // Hide the preview view for the file item that is being renamed. The rename controller will put a view in the same spot on the screen and will animate it into place.
    OUIWithoutAnimating(^{
        OUIDocumentPickerFileItemView *fileItemView = [_picker.activeScrollView fileItemViewForFileItem:_fileItem];
        OBASSERT(fileItemView);
        fileItemView.renaming = YES;
    });

    // Get laid out in the original configuration
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];

    // Set up for reconfiguration...
    _renameStarted = YES;
    [self.view setNeedsLayout];

    // We let the keyboard drive our animation so that we can sync with it.
    // OUIMainViewController listens for keyboard notifications and publishes OUIMainViewControllerResizedForKeyboard after it has adjusted its content view appropriately.
    [_nameTextField becomeFirstResponder];
    
    // We should get notified of the keyboard showing by the time the method above returns, unless it is a hardware keyboard. In that case, the keyboard won't drive the animation and we need to.
    if (!_keyboardVisible) {
        [UIView beginAnimations:@"Start renaming animating without keyboard driver" context:NULL];
        [self.view layoutIfNeeded];
        [UIView commitAnimations];
    }
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];

    view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    
    _previewView = [[OUIDocumentPreviewView alloc] initWithFrame:CGRectZero];
    
    // Pre-populate the preview to avoid reloading it.
    {
        OUIDocumentPickerFileItemView *fileItemView = [_picker.activeScrollView fileItemViewForFileItem:_fileItem];
        OBASSERT(!fileItemView.loadingPreviews);
        
        NSArray *previews = fileItemView.previewView.previews;
        OBASSERT([previews count] == 1);
        
        OUIDocumentPreview *preview = [previews lastObject];
        if (preview)
            [_previewView addPreview:preview];
    }
    
    [view addSubview:_previewView];
    
    _nameTextField = [[UITextField alloc] initWithFrame:CGRectZero];
    _nameTextField.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin; 
    _nameTextField.font = [UIFont systemFontOfSize:[UIFont labelFontSize]];
    _nameTextField.textColor = [UIColor blackColor];
    _nameTextField.textAlignment = UITextAlignmentCenter;
    _nameTextField.borderStyle = UITextBorderStyleRoundedRect;
    _nameTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    _nameTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _nameTextField.spellCheckingType = UITextSpellCheckingTypeNo;
    _nameTextField.delegate = self;
    _nameTextField.alpha = 0; // start hidden
    [_nameTextField sizeToFit]; // get the right height
    _nameTextField.text = _fileItem.editingName;
    [view addSubview:_nameTextField];
    
    OBFinishPortingLater("Add shield view that only passes through events for the text field.");
    
    self.view = view;
    [view release];
}

- (void)viewDidUnload;
{
    [super viewDidUnload];

    [_previewView release];
    _previewView = nil;
    
    [_nameTextField release];
    _nameTextField = nil;
}

- (void)willMoveToParentViewController:(UIViewController *)parent;
{
    if (parent) {
        // Reset the toolbar items
        {
            NSString *title = nil;
            id <OUIDocumentPickerDelegate> delegate = _picker.delegate;
            if ([delegate respondsToSelector:@selector(documentPicker:toolbarPromptForRenamingFileItem:)])
                title = [delegate documentPicker:_picker toolbarPromptForRenamingFileItem:_fileItem];
            if (!title)
                title = NSLocalizedStringFromTableInBundle(@"Rename Document", @"OmniUI", OMNI_BUNDLE, @"toolbar prompt while renaming a document");
            
            OBFinishPortingLater("Use a \"center these words on screen\" toolbar item.");
            
            UIBarButtonItem *leftSpace = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
            UIBarButtonItem *titleItem = [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStylePlain target:nil action:NULL] autorelease];
            UIBarButtonItem *rightSpace = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
            UIBarButtonItem *doneItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_done:)] autorelease];
            
            OUIWithoutAnimating(^{
                _picker.toolbar.items = [NSArray arrayWithObjects:leftSpace, titleItem, rightSpace, doneItem, nil];
                [_picker.toolbar layoutIfNeeded];
            });
        }
        
    } else {
        OBASSERT(_isRegisteredAsFilePresenter == NO);
        
        // We should be removed before the file item goes away (maybe due to an incoming iCloud edit).
        OBASSERT([_picker.documentStore.fileItems member:_fileItem] == _fileItem);

        // Restore the toolbar. We set its toolbar's items w/o calling -setToolbarItems: on the picker itself.
        OUIWithoutAnimating(^{
            _picker.toolbar.items = _picker.toolbarItems;
            [_picker.toolbar layoutIfNeeded];
        });
    }
    
    [super willMoveToParentViewController:parent];
}

- (void)didMoveToParentViewController:(UIViewController *)parent;
{
    [super didMoveToParentViewController:parent];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    // Due to a bug in iOS 5, didMoveToParentViewController: currently gets called twice. Don't sign up for notifications extra times.
    if (parent && !_registeredForNotifications) {
        _registeredForNotifications = YES;
        [center addObserver:self selector:@selector(_resizeForKeyboard:) name:OUIMainViewControllerResizedForKeyboard object:nil];
        [center addObserver:self selector:@selector(_keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    } else if (!parent && _registeredForNotifications) {
        _registeredForNotifications = NO;
        [center removeObserver:self name:OUIMainViewControllerResizedForKeyboard object:nil];
        [center removeObserver:self name:UIKeyboardDidHideNotification object:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    // Make sure our initial layout is right, at least for the name field, which shouldn't animate frame unless we are rotating
    [self.view layoutIfNeeded];
}

- (void)viewDidLayoutSubviews;
{
    UIView *view = self.view;
    CGRect bounds = view.bounds;

    // Center the preview in the middle 1/3 of our bounds. Don't constrain the height; just the width. Otherwise, with the keyboard up and aspect ratio preservation on, the preview is too small.
    CGRect targetPreviewFrame;
    targetPreviewFrame.origin.x = floor(CGRectGetMinX(bounds) + CGRectGetWidth(bounds) / 3.0);
    targetPreviewFrame.origin.y = CGRectGetMinY(bounds);
    targetPreviewFrame.size.width = ceil(CGRectGetWidth(bounds) / 3.0);
    targetPreviewFrame.size.height = CGRectGetHeight(bounds);

    RENAME_DEBUG(@"Layout with rename started %d", _renameStarted);

    CGRect editingFrame = _nameTextField.frame;
    CGFloat heightMargin = editingFrame.size.height;
    CGRect previewFrame;
    if (_renameStarted) {
        // Fade out the other preview views (and the label/details for the renaming file item).
        _picker.activeScrollView.alpha = 0;

        targetPreviewFrame.size.height -= (editingFrame.size.height + 3*heightMargin);     // 3 = margin below text field + margin above text field + margin above preview
        targetPreviewFrame.origin.y += editingFrame.size.height;
        previewFrame = [_previewView previewRectInFrame:targetPreviewFrame];
        
        _nameTextField.alpha = 1;
    } else {
        _picker.activeScrollView.alpha = 1;

        // Put the preview view right over where it would be normally.
        OUIDocumentPickerFileItemView *fileItemView = [_picker.activeScrollView fileItemViewForFileItem:_fileItem];
        OBASSERT(fileItemView);
        
        OUIDocumentPreviewView *originalPreviewView = fileItemView.previewView;
        previewFrame = [view convertRect:originalPreviewView.bounds fromView:originalPreviewView];
        
        _nameTextField.alpha = 0;
    }
    
    _previewView.frame = previewFrame;
    
    // Center the editing field vertically under the preview
    editingFrame.size.width = ceil(CGRectGetWidth(bounds) / 3.0);
    editingFrame.origin.x = floor(CGRectGetMidX(bounds) - 0.5 * editingFrame.size.width);

    CGFloat remainingHeight = CGRectGetMaxY(bounds) - CGRectGetMaxY(previewFrame) - heightMargin;    
    editingFrame.origin.y = floor(CGRectGetMaxY(previewFrame) + remainingHeight/2 - CGRectGetHeight(editingFrame)/2);
    if (CGRectGetMaxY(editingFrame) > (CGRectGetMaxY(bounds) - heightMargin - CGRectGetHeight(editingFrame)))   
        editingFrame.origin.y = CGRectGetMaxY(bounds) - heightMargin - CGRectGetHeight(editingFrame);   // this will at least guarantee that we are not under the keyboard

    _nameTextField.frame = editingFrame;
}

#pragma mark -
#pragma mark UITextField delegate

- (void)_performEndingAnimationIfNeeded;
{
    // If we are renaming and there is no keyboard visibile, we are using a hardware keyboard -- we won't get notified of the keyboard hiding and it can't control the animation, so we must do it ourselves
    if (_renameStarted && !_keyboardVisible) {
        static const NSTimeInterval kKeyboardAnimationInterval = 0.25; // experimentally
        static const UIViewAnimationCurve kKeyboardAnimationCurve = UIViewAnimationCurveEaseInOut;
        
        [OUIAnimationSequence runWithDuration:kKeyboardAnimationInterval actions:
         ^{
             [UIView setAnimationCurve:kKeyboardAnimationCurve];
             [self _startRenameStateChange:NO withDuration:kKeyboardAnimationInterval curve:kKeyboardAnimationCurve];
             [self.view layoutIfNeeded];
         },
         ^{
             [self _finishRenameAfterHidingKeyboard];
         },
         nil];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    RENAME_DEBUG(@"textFieldDidEndEditing:");
    
    OBFinishPortingLater("Actually do some renaming and make sure that we scroll the renamed file item to visible (or check whether iWork bothers)");
    
    
    NSString *newName = [textField text];
    if ([NSString isEmptyString:newName] || [newName isEqualToString:_fileItem.name]) {
        OBFinishPortingLater("What should we do about disabling rotation while renaming? Probably nothing and disableRotationDisplay should be removed.");
        //_activeScrollView.disableRotationDisplay = NO;
        //_activeScrollView.disableScroll = NO;
        [self _performEndingAnimationIfNeeded];
        return;
    }
    
    NSURL *currentURL = _fileItem.fileURL;
    NSString *uti = [OFSFileInfo UTIForURL:currentURL];
    OBASSERT(uti);
    
    // We have no open documents at this point, so we don't need to synchronize with UIDocument autosaving via -performAsynchronousFileAccessUsingBlock:. We do want to prevent other documents from opening, though.
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    [_picker.documentStore renameFileItem:_fileItem baseName:newName fileType:uti completionQueue:[NSOperationQueue mainQueue] handler:^(NSURL *destinationURL, NSError *error){
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        
        if (!destinationURL) {
            NSLog(@"Error renaming document with URL \"%@\" to \"%@\" with type \"%@\": %@", [currentURL absoluteString], newName, uti, [error toPropertyList]);
            
            NSString *msg = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to rename document to %@", @"OmniUI", OMNI_BUNDLE, @"error when renaming a document"), newName];                
            NSError *err = [[NSError alloc] initWithDomain:NSURLErrorDomain code:0 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:msg, NSLocalizedDescriptionKey, msg, NSLocalizedFailureReasonErrorKey, nil]];
            OUI_PRESENT_ERROR(err);
            [err release];
        }
    }];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    // <bug://bugs/61021>
    NSRange r = [string rangeOfString:@"/"];
    if (r.location != NSNotFound) {
        return NO;
    }
    
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField;
{
    RENAME_DEBUG(@"textFieldShouldClear:");
    
    [_nameTextField becomeFirstResponder];
    [_nameTextField setDelegate:self];  // seems to be a hardware keyboard bug where clearing the text clears the delegate if no keyboard is showing

    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    RENAME_DEBUG(@"textFieldShouldReturn:");

    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    main_async(^{
        [_nameTextField resignFirstResponder];
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    });
    
    return YES;
}

#pragma mark -
#pragma mark NSFilePresenter

- (NSURL *)presentedItemURL;
{
    return _presentedFileURL;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    return _filePresenterQueue;
}

// We don't currently attempt to reset our in-progress edit of the file name if we see an incoming rename. We just bail
- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    // Acknowledge the change, in case we are asked when we -removeFilePresenter:
    [_presentedFileURL autorelease];
    _presentedFileURL = [newURL copy];
    
    // But then cancel ourselves
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _cancel];
    }];
}

- (void)presentedItemDidChange;
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _cancel];
    }];
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *))completionHandler;
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self _cancel];
        
        if (completionHandler)
            completionHandler(nil);
    }];
}

#pragma mark -
#pragma mark Private

- (void)_cancel;
{
    // Clear the text field (which will be interpreted as leaving the name alone) and pretend the Done button was tapped
    _nameTextField.text = @"";
    [self _done:nil];
}

- (void)_done:(id)sender;
{
    RENAME_DEBUG(@"_done:");

    OBFinishPortingLater("Do the actual rename. Might want an \"abort\" variant if we get an incoming change that invalidates our items");
    
    // Let the keyboard drive the animation
    [_nameTextField resignFirstResponder];
}

// We'll need to factor out a public -stopRenaming for use by OUIDocumentPicker when it wants to abort a rename (incoming iCloud change involving the file item).
- (void)_startRenameStateChange:(BOOL)renaming withDuration:(NSTimeInterval)animationInterval curve:(UIViewAnimationCurve)animationCurve;
{
    RENAME_DEBUG(@"_startRenameStateChange:%d withDuration:%f curve:%d", renaming, animationInterval, animationCurve);

    _previewView.animationDuration = animationInterval;
    _previewView.animationCurve = animationCurve;
    
    if (renaming == NO) {
        OBASSERT(_renameStarted == YES);
        _renameStarted = NO;
    } else {
        OBASSERT(_renameStarted == YES); // already set
    }
    
    [self.view setNeedsLayout];
}

- (void)_finishRenameAfterHidingKeyboard;
{
    OBPRECONDITION(_keyboardVisible == NO);
    
    OBASSERT(_isRegisteredAsFilePresenter);
    if (_isRegisteredAsFilePresenter) {
        _isRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
    
    // Unhide the preview view we hid above
    OUIWithoutAnimating(^{
        OUIDocumentPickerFileItemView *fileItemView = [_picker.activeScrollView fileItemViewForFileItem:_fileItem];
        OBASSERT(fileItemView);
        fileItemView.renaming = NO;
    });
    
    [_picker _didStopRenamingFileItem];
}

- (void)_resizeForKeyboard:(NSNotification *)note;
{
    RENAME_DEBUG(@"_resizeForKeyboard: %@", note);

    [self.view setNeedsLayout];
    
    NSNumber *visibility = [[note userInfo] objectForKey:OUIMainViewControllerResizedForKeyboardVisibilityKey];
    OBASSERT(visibility);
    
    _keyboardVisible = [visibility boolValue];
    
    NSDictionary *originalInfo = [[note userInfo] objectForKey:OUIMainViewControllerResizedForKeyboardOriginalUserInfoKey];
    NSNumber *duration = [originalInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey];
    NSNumber *curve = [originalInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey];
    
    OBASSERT(duration);
    OBASSERT(curve);
    
    if ([visibility boolValue]) {
        OBASSERT(_renameStarted); // Should have been set already and then the text field made first responder, causing this notification
    } else {
        OBASSERT(_renameStarted); // Should stil be true; this is how we find out that that keyboard is going away and soon (but maybe not yet) the text field will lose first responder status
    }
    
    [self _startRenameStateChange:_keyboardVisible withDuration:[duration doubleValue] curve:[curve intValue]];
}

- (void)_keyboardDidHide:(NSNotification *)note;
{
    RENAME_DEBUG(@"_keyboardDidHide: %@", note);

    _keyboardVisible = NO;
    [self _finishRenameAfterHidingKeyboard];
}

@end
