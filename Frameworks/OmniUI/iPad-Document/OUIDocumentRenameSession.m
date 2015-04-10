// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentRenameSession.h"

#import <OmniUIDocument/OUIDocumentPickerItemMetadataView.h>
#import <OmniDocumentStore/ODSErrors.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniUI/OUIInteractionLock.h>
#import <OmniUI/OUIKeyboardNotifier.h>
#import <OmniUI/OUIShieldView.h>

#import "OUIDocumentPickerViewController-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define RENAME_DEBUG(format, ...) NSLog(@"RENAME: " format, ## __VA_ARGS__)
#else
    #define RENAME_DEBUG(format, ...)
#endif

@interface OUIDocumentRenameSession () <UITextFieldDelegate, NSFilePresenter, OUIShieldViewDelegate>
@end

@implementation OUIDocumentRenameSession
{
    OUIDocumentPickerViewController *_picker;
    UITextField *_nameTextField;
    ODSItem *_item;
    OUIShieldView *_dimmingView;
    
    NSString *_originalName;
    NSOperationQueue *_filePresenterQueue;
    NSURL *_presentedFileURL; // Remember the original file URL in case there is an incoming rename; we want to be able to respond to NSFilePresenter -presentedItemURL correctly in this case.
    
    BOOL _isRegisteredAsFilePresenter;
    BOOL _isAttemptingRename;
    BOOL _isEndingEditing;
    BOOL _isFinishedRenaming;
    
    NSTimeInterval _animationDuration;
    UIViewAnimationCurve _animationCurve;
}

- initWithDocumentPicker:(OUIDocumentPickerViewController *)picker itemView:(OUIDocumentPickerItemView *)itemView;
{
    OBPRECONDITION(picker);
    OBPRECONDITION(itemView);
    
    if (!(self = [super init]))
        return nil;
    
    _picker = picker;
    _itemView = itemView;
    _item = itemView.item;
    OBASSERT([picker.folderItem.childItems member:_item] == _item);

    // We temporarily become the delegate.
    _nameTextField = _itemView.metadataView.nameTextField;
    _nameTextField.delegate = self;
    
    // Kinda gross...
    UIView *superview = _itemView.superview;
    _dimmingView = [OUIShieldView shieldViewWithView:superview];
    _dimmingView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; // Match on device rotation
    _dimmingView.opaque = NO;
    _dimmingView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.2];
    _dimmingView.alpha = 0;
    _dimmingView.delegate = self;
    [superview bringSubviewToFront:_itemView];
    [superview insertSubview:_dimmingView belowSubview:_itemView];
    
    OUIKeyboardNotifier *notifier = [OUIKeyboardNotifier sharedNotifier];
    [UIView animateWithDuration:notifier.lastAnimationDuration animations:^{
        _dimmingView.alpha = 1;
    }];
    
    _originalName = [_nameTextField.text copy];
    if (_item.type == ODSItemTypeFile && [_item isKindOfClass:[ODSFileItem class]]) {
        _nameTextField.text = [(ODSFileItem *)_item editingName];
    }
    
    // TODO: Maybe -fileURL should be on ODSFolderItem too.
    if (_item.type == ODSItemTypeFolder)
        _presentedFileURL = [[_item.scope.documentsURL URLByAppendingPathComponent:((ODSFolderItem *)_item).relativePath isDirectory:YES] copy];
    else
        _presentedFileURL = [((ODSFileItem *)_item).fileURL copy];
    
    _filePresenterQueue = [[NSOperationQueue alloc] init];
    _filePresenterQueue.name = @"OUIDocumentRenameSession NSFilePresenter notifications";
    _filePresenterQueue.maxConcurrentOperationCount = 1;

    // Load these with some experimentally determined values to match the keyboard animation. If the keyboard does notify us, we'll use whatever it sent for real.
    _animationDuration = 0.25;
    _animationCurve = UIViewAnimationCurveEaseInOut;

    // This will retain us, so we cannot -removeFilePresenter: in dealloc.
    [NSFileCoordinator addFilePresenter:self];
    _isRegisteredAsFilePresenter = YES;
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_nameTextField.delegate != self);
    OBPRECONDITION(!_isRegisteredAsFilePresenter);
    
    _dimmingView.delegate = nil;
}

- (void)cancelRenaming;
{
    RENAME_DEBUG(@"cancelRenaming");
    
    // Put the original name back. This will cause -_done: to bail on the rename.
    _nameTextField.text = _originalName;
    
    [self _done:nil];
}

- (void)layoutDimmingView;
{
    UIView *superview = _itemView.superview;
    _dimmingView.frame = superview.bounds;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
{
    RENAME_DEBUG(@"textFieldShouldEndEditing:");
    
    // We need an extra BOOL here to let us know we should really go ahead and end the rename.
    // The rename operation doesn't call our completion block until the file presenter queue has performed the -presentedItemDidMoveToURL:, but in that case the file item will have only updated its _filePresenterURL (which must update immediately and which can be accessed from any thead) and has only enqueued a main thread operation to update its _displayedFileURL (which is what sources the -name method below). The ordering of operations will still be correct since our completion block will still get called on the main thread after the display name is updated, but we can't tell that here.
    NSString *newName = [textField text];
    BOOL isEmpty = [NSString isEmptyString:newName];
    BOOL usingEditingName = (_item.type == ODSItemTypeFile && [_item isKindOfClass:[ODSFileItem class]]);
    NSString *nameTest = usingEditingName ? [(ODSFileItem *)_item editingName] : _item.name;

    BOOL isSameName = isEmpty || ([nameTest localizedCompare:newName] == NSOrderedSame);
    if (_isAttemptingRename || _isFinishedRenaming || isSameName) {
        if (isSameName) {
            _isFinishedRenaming = YES;
            
            // Might be the "same" due to deleting everything
            if (isEmpty || (usingEditingName && !_isEndingEditing))
                _nameTextField.text = _originalName;
        }
        
        if (_isEndingEditing == NO) // Avoid infinite recursion
            [self _done:nil];
        RENAME_DEBUG(@"Bail on empty/same name");
        return YES;
    }
        
    // Otherwise, start the rename and return NO for now, but remember that we've tried already.
    _isAttemptingRename = YES;
    
    [_picker _renameItem:_item baseName:newName completionHandler:^(NSError *errorOrNil){
        if (errorOrNil) {
            if ([errorOrNil hasUnderlyingErrorDomain:ODSErrorDomain code:ODSFilenameAlreadyInUse]) {
                // Leave the fixed name for the user to try again.
                _isAttemptingRename = NO;
            } else {
                // Some other error which may not be correctable -- bail
                _isFinishedRenaming = YES;
                [_nameTextField endEditing:YES];
            }
        } else {
            // We are all good. Clear this now so that we don't get reentrantly called.
            _isFinishedRenaming = YES;
            [self _done:nil];
        }
    }];
    
    return NO;
}

- (void)textFieldDidEndEditing:(NSNotification *)note;
{
    RENAME_DEBUG(@"did end editing");
    RENAME_DEBUG(@"  _isAttemptingRename %d", _isAttemptingRename);
    
    OBASSERT(_nameTextField.delegate == self);
    _nameTextField.delegate = nil;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField{
    [textField resignFirstResponder];
    return NO;
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

#pragma mark - NSFilePresenter

- (NSURL *)presentedItemURL;
{
    NSURL *result = nil;
    
    @synchronized(self) {
        result = _presentedFileURL;
    }
    
    return result;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    OBPRECONDITION(_filePresenterQueue);
    return _filePresenterQueue;
}

// We don't currently attempt to reset our in-progress edit of the file name if we see an incoming rename. We just bail
- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    @synchronized(self) {
        if (OFISEQUAL(_presentedFileURL, newURL))
            return;

        // Acknowledge the change, in case we are asked when we -removeFilePresenter:
        _presentedFileURL = [newURL copy];
    }
    
    // But then cancel ourselves (unless we are the one doing the rename)
    if (_isAttemptingRename == NO) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self cancelRenaming];
        }];
    }
}

- (void)presentedItemDidChange;
{
    // This gets spuriously sent after renames sometimes, but if there is an incoming edit from iCloud (or iTunes, once that works again), discard our rename.
    if (_isAttemptingRename == NO) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self cancelRenaming];
        }];
    }
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *))completionHandler;
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self cancelRenaming];
        
        if (completionHandler)
            completionHandler(nil);
    }];
}

#pragma mark - OUIShieldViewDelegate

- (void)shieldViewWasTouched:(OUIShieldView *)shieldView;
{
    [self _done:shieldView];
}

#pragma mark - Private

- (void)_done:(id)sender;
{
    // Let the keyboard drive the animation
    RENAME_DEBUG(@"-_done: calling -endEditing:");
    RENAME_DEBUG(@"  _isAttemptingRename %d", _isAttemptingRename);
    
    UIView *dimmingView = _dimmingView;
    OUIKeyboardNotifier *notifier = [OUIKeyboardNotifier sharedNotifier];
    [UIView animateWithDuration:notifier.lastAnimationDuration animations:^{
        [UIView setAnimationCurve:notifier.lastAnimationCurve];
        dimmingView.alpha = 0;
    } completion:^(BOOL finished){
        [dimmingView removeFromSuperview];
    }];
    _dimmingView = nil;
    
    // Depending on how the user ends editing, we can get called first or -textFieldShouldEndEditing:.
    _isEndingEditing = YES;
    BOOL rc = [_nameTextField endEditing:NO];
    _isEndingEditing = NO;
    
    if (rc == NO && _isAttemptingRename) {
        // Our -textFieldShouldEndEditing: call rejected the edit so that we want wait to see if the rename actually worked before ending editing.
        RENAME_DEBUG(@"Rename is in progress -- waiting for it to finish or fail");
        return;
    }
    
    RENAME_DEBUG(@"-_done:, after -endEditing:...");
    RENAME_DEBUG(@"  _isAttemptingRename %d", _isAttemptingRename);

    OBASSERT(_isFinishedRenaming);
    
    OBRetainAutorelease(self); // Make sure we don't get deallocated immediately since our call stack still has stuff to do.
    
    OBASSERT(_isRegisteredAsFilePresenter);
    if (_isRegisteredAsFilePresenter) {
        _isRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
}

@end
