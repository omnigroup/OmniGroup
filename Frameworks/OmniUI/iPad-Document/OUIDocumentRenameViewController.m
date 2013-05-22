// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentRenameViewController.h"

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUIDocument/OUIDocumentPickerDelegate.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIMainViewController.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIShieldView.h>
//#import <OmniQuartz/CALayer-OQExtensions.h>

#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define RENAME_DEBUG(format, ...) NSLog(@"RENAME: " format, ## __VA_ARGS__)
#else
    #define RENAME_DEBUG(format, ...)
#endif

/*
 
 With the software keyboard, we need to do our work inside the keyboard resize callbacks so that our transition syncs up with the keyboard. We get notifications like so:
 
 2012-01-19 13:05:48.782 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x1a8160 {name = UITextFieldTextDidBeginEditingNotification; object = <UITextField: 0x189f10; frame = (20 20; 97 31); text = ''; clipsToBounds = YES; opaque = NO; autoresize = RM+BM; layer = <CALayer: 0x179830>>}
 2012-01-19 13:05:48.791 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x1b0220 {name = UIKeyboardWillChangeFrameNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 }}
 2012-01-19 13:05:48.793 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0xee90220 {name = UIKeyboardWillShowNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 }}
 2012-01-19 13:05:49.073 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0xeeb5c20 {name = UIKeyboardDidChangeFrameNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 }}
 2012-01-19 13:05:49.076 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x1ab510 {name = UIKeyboardDidShowNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 }}
 2012-01-19 13:05:54.057 KeyboardNotficationTest[1453:707] -done:
 2012-01-19 13:05:54.063 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x1952e0 {name = UIKeyboardWillChangeFrameNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 }}
 2012-01-19 13:05:54.066 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0xeeb3060 {name = UIKeyboardWillHideNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 }}
 2012-01-19 13:05:54.070 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x19e8d0 {name = UITextFieldTextDidEndEditingNotification; object = <UITextField: 0x189f10; frame = (20 20; 97 31); text = ''; clipsToBounds = YES; opaque = NO; autoresize = RM+BM; layer = <CALayer: 0x179830>>}
 2012-01-19 13:05:54.327 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x19c8c0 {name = UIKeyboardDidChangeFrameNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 }}
 2012-01-19 13:05:54.329 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0xeeb7470 {name = UIKeyboardDidHideNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 }}

 With the software keyboard, on device rotation, we get a storm of hide/show/resize animations. We cannot easily determine that we've started/stopped editing based on the keyboard show/hide (though maybe we could use the UIKeyboardFrameChangedByUserInteraction key, but so far as I see it is undocumented, so we shouldn't).
 
 2012-01-19 13:07:02.785 KeyboardNotficationTest[1453:707] will rotate
 2012-01-19 13:07:02.789 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0xee9d5d0 {name = UIKeyboardWillChangeFrameNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 }}
 2012-01-19 13:07:02.792 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0xee9d5d0 {name = UIKeyboardWillHideNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 }}
 2012-01-19 13:07:02.813 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x1af2b0 {name = UIKeyboardDidChangeFrameNotification; userInfo = {
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 }}
 2012-01-19 13:07:02.816 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x1af2b0 {name = UIKeyboardDidHideNotification; userInfo = {
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {1024, 352}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {512, 592}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {512, 944}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 0}, {352, 1024}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{-352, 0}, {352, 1024}}";
 }}
 2012-01-19 13:07:02.933 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0xeeb1b70 {name = UIKeyboardWillChangeFrameNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {768, 264}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {384, 1156}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {384, 892}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 760}, {768, 264}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 760}, {768, 264}}";
 }}
 2012-01-19 13:07:02.935 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x19d7f0 {name = UIKeyboardWillShowNotification; userInfo = {
 UIKeyboardAnimationCurveUserInfoKey = 0;
 UIKeyboardAnimationDurationUserInfoKey = "0.25";
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {768, 264}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {384, 1156}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {384, 892}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 1024}, {768, 264}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 760}, {768, 264}}";
 }}
 2012-01-19 13:07:03.352 KeyboardNotficationTest[1453:707] did rotate
 2012-01-19 13:07:03.354 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x195a90 {name = UIKeyboardDidChangeFrameNotification; userInfo = {
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {768, 264}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {384, 1156}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {384, 892}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 1024}, {768, 264}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 760}, {768, 264}}";
 }}
 2012-01-19 13:07:03.357 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x195a90 {name = UIKeyboardDidShowNotification; userInfo = {
 UIKeyboardBoundsUserInfoKey = "NSRect: {{0, 0}, {768, 264}}";
 UIKeyboardCenterBeginUserInfoKey = "NSPoint: {384, 1156}";
 UIKeyboardCenterEndUserInfoKey = "NSPoint: {384, 892}";
 UIKeyboardFrameBeginUserInfoKey = "NSRect: {{0, 1024}, {768, 264}}";
 UIKeyboardFrameChangedByUserInteraction = 0;
 UIKeyboardFrameEndUserInfoKey = "NSRect: {{0, 760}, {768, 264}}";
 }}

 
 With a hardware keyboard attached, we get no notifications about show/hide/resize from the keyboard, so we have to drive the transition ourselves
 
 2012-01-19 13:02:58.411 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0x19d460 {name = UITextFieldTextDidBeginEditingNotification; object = <UITextField: 0x189f10; frame = (20 20; 97 31); text = ''; clipsToBounds = YES; opaque = NO; autoresize = RM+BM; layer = <CALayer: 0x179830>>}
 2012-01-19 13:03:05.448 KeyboardNotficationTest[1453:707] -done:
 2012-01-19 13:03:05.457 KeyboardNotficationTest[1453:707] note: NSConcreteNotification 0xeeac530 {name = UITextFieldTextDidEndEditingNotification; object = <UITextField: 0x189f10; frame = (20 20; 97 31); text = ''; clipsToBounds = YES; opaque = NO; autoresize = RM+BM; layer = <CALayer: 0x179830>>}

 */

@interface OUIDocumentRenameViewController () <UITextFieldDelegate, NSFilePresenter>

@property (nonatomic, strong) OUIShieldView *shieldView;

- (void)_setupPreviewWithOrientation:(UIInterfaceOrientation)orientation;
- (void)_cancel;
- (void)_done:(id)sender;
- (void)_prepareToResizeWithDuration:(NSTimeInterval)animationInterval curve:(UIViewAnimationCurve)animationCurve;
- (void)_finishRenameAfterHidingKeyboard;
- (void)_didBeginResizingForKeyboard:(NSNotification *)note;
- (void)_didFinishResizingForKeyboard:(NSNotification *)note;
@end

@implementation OUIDocumentRenameViewController
{
    OUIDocumentPicker *_picker;
    OFSDocumentStoreFileItem *_fileItem;
    
    NSOperationQueue *_filePresenterQueue;
    NSURL *_presentedFileURL; // Remember the original file URL in case there is an incoming rename; we want to be able to respond to NSFilePresenter -presentedItemURL correctly in this case.
    
    BOOL _isRegisteredAsFilePresenter;
    BOOL _didMoveToParentAlready;

    BOOL _receivedKeyboardWillResize;
    BOOL _textFieldEditing;
    BOOL _textFieldIsEndingEditing;
    BOOL _isAttemptingRename;
    BOOL _shouldSendFinishRenameAfterKeyboardResizes;
    
    OUIDocumentPreviewView *_previewView;
    UITextField *_nameTextField;
    
    OUIDocumentPickerFileItemView *_renamingFileItemView;
    
    NSTimeInterval _animationDuration;
    UIViewAnimationCurve _animationCurve;
}

- initWithDocumentPicker:(OUIDocumentPicker *)picker fileItem:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(picker);
    OBPRECONDITION(fileItem);
    OBPRECONDITION([picker.selectedScope.fileItems member:fileItem] == fileItem);
    
    if (!(self = [super init]))
        return nil;
    
    _picker = picker;
    _fileItem = fileItem;
    
    _presentedFileURL = [_fileItem.fileURL copy];
    _filePresenterQueue = [[NSOperationQueue alloc] init];
    _filePresenterQueue.name = @"OUIDocumentRenameViewController NSFilePresenter notifications";
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
    OBPRECONDITION(_didMoveToParentAlready == NO);
    
    if (_didMoveToParentAlready) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center removeObserver:self name:OUIMainViewControllerDidBeginResizingForKeyboard object:nil];
        [center removeObserver:self name:OUIMainViewControllerDidFinishResizingForKeyboard object:nil];
        
        [self.shieldView removeFromSuperview];
        self.shieldView = nil;
    }
    
    OBASSERT(_renamingFileItemView == nil);
}

- (void)startRenaming;
{
    RENAME_DEBUG(@"-startRenaming");
    
    // Hide the preview view for the file item that is being renamed. The rename controller will put a view in the same spot on the screen and will animate it into place.
    OUIWithoutAnimating(^{
        // Hold onto the exact view we set the flag on so that we make sure to turn it off on the exact same one. If the picker scrolls for some reason, it might assign a different item view.
        OBASSERT(_renamingFileItemView == nil);
        _renamingFileItemView = [_picker.activeScrollView fileItemViewForFileItem:_fileItem];
        OBASSERT(_renamingFileItemView);
        _renamingFileItemView.renaming = YES;
    });

    // Get laid out in the original configuration
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];

    // Make sure this isn't spuriously set by a software keyboard being toggled in/out with a hardware keyboard attached
    _receivedKeyboardWillResize = NO;
    
    // We let the keyboard drive our animation so that we can sync with it.
    // OUIMainViewController listens for keyboard notifications and publishes OUIMainViewControllerDid{Begin,Finish}ResizingForKeyboard after it has adjusted its content view appropriately.
    [_nameTextField becomeFirstResponder];
    RENAME_DEBUG(@"  becomeFirstResponder returned");

    // If the software keyboard is going to be used, we should have received a notification about its frame changing by now. If we didn't, then a hardware keyboard is being used and we have to drive the animation.
    if (_receivedKeyboardWillResize == NO) {
        [UIView beginAnimations:@"Start renaming" context:NULL];
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        [UIView commitAnimations];
    } else {
        _receivedKeyboardWillResize = NO;
    }
}

- (void)cancelRenaming;
{
    [self _cancel];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];

    //OQSetAnimationLoggingEnabledForLayer(view.layer, YES);
    
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    
    _previewView = [[OUIDocumentPreviewView alloc] initWithFrame:CGRectZero];
    [self _setupPreviewWithOrientation:self.interfaceOrientation];
    
    [view addSubview:_previewView];
    
    _nameTextField = [[UITextField alloc] initWithFrame:CGRectZero];
    _nameTextField.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin; 
    _nameTextField.font = [UIFont fontWithName:@"Helvetica-Bold" size:20];
    _nameTextField.textColor = [UIColor blackColor];
    _nameTextField.textAlignment = NSTextAlignmentCenter;
    _nameTextField.borderStyle = UITextBorderStyleRoundedRect;
    _nameTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    _nameTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _nameTextField.spellCheckingType = UITextSpellCheckingTypeNo;
    _nameTextField.returnKeyType = UIReturnKeyDone;
    _nameTextField.delegate = self;
    _nameTextField.alpha = 0; // start hidden
    [_nameTextField sizeToFit]; // get the right height
    _nameTextField.text = _fileItem.editingName;
        
    //OQSetAnimationLoggingEnabledForLayer(_nameTextField.layer, NO);
    
    [view addSubview:_nameTextField];
    
    self.view = view;
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
                title = NSLocalizedStringFromTableInBundle(@"Rename Document", @"OmniUIDocument", OMNI_BUNDLE, @"toolbar prompt while renaming a document");
            
            UIBarButtonItem *leftSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
            UIBarButtonItem *titleItem = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStylePlain target:nil action:NULL];
            UIBarButtonItem *rightSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
            UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_done:)];

            OB_UNUSED_VALUE(leftSpace); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning
            OB_UNUSED_VALUE(titleItem); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning
            OB_UNUSED_VALUE(rightSpace); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning
            OB_UNUSED_VALUE(doneItem); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning

            NSArray *items = [NSArray arrayWithObjects:leftSpace, titleItem, rightSpace, doneItem, nil];
            [_picker.toolbar setItems:items animated:YES];
        }
        
    } else {
        OBASSERT(_isRegisteredAsFilePresenter == NO);
        
        // We should be removed before the file item goes away (maybe due to an incoming iCloud edit).
        OBASSERT([_picker.selectedScope.fileItems member:_fileItem] == _fileItem);

        // Restore the toolbar. We set its toolbar's items w/o calling -setToolbarItems: on the picker itself.
        [_picker.toolbar setItems:_picker.toolbarItems animated:YES];
    }
    
    [super willMoveToParentViewController:parent];
}

- (void)didMoveToParentViewController:(UIViewController *)parent;
{
    [super didMoveToParentViewController:parent];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    // Due to a bug in iOS 5, didMoveToParentViewController: currently gets called twice. Don't sign up for notifications extra times.
    if (parent && !_didMoveToParentAlready) {
        _didMoveToParentAlready = YES;
        [center addObserver:self selector:@selector(_didBeginResizingForKeyboard:) name:OUIMainViewControllerDidBeginResizingForKeyboard object:nil];
        [center addObserver:self selector:@selector(_didFinishResizingForKeyboard:) name:OUIMainViewControllerDidFinishResizingForKeyboard object:nil];
        
        // Add shieldview now that we know who our window is.
        OBASSERT_NULL(_shieldView);
        
        UITapGestureRecognizer *shieldViewTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_shieldViewTapped:)];
        NSArray *passthroughViews = @[_nameTextField];
        
        UIWindow *window = self.view.window;
        OBASSERT_NOTNULL(window);
        
        self.shieldView = [OUIShieldView shieldViewWithView:window];
        [self.shieldView addGestureRecognizer:shieldViewTapRecognizer];
        self.shieldView.passthroughViews = passthroughViews;
        
        [window addSubview:self.shieldView];

    } else if (!parent && _didMoveToParentAlready) {
        _didMoveToParentAlready = NO;
        [center removeObserver:self name:OUIMainViewControllerDidBeginResizingForKeyboard object:nil];
        [center removeObserver:self name:OUIMainViewControllerDidFinishResizingForKeyboard object:nil];
    }
}

- (void)viewWillLayoutSubviews;
{
    UIView *view = self.view;
    CGRect bounds = view.bounds;

    BOOL landscape = _previewView.landscape;
    
    CGFloat previewToLabelGap = landscape ? 37 : 50;
    CGFloat nameTextFieldWidth = landscape ? 307 : 340;
    CGSize targetPreviewSize = landscape ? CGSizeMake(311, 236) : CGSizeMake(197, 254);
    
    RENAME_DEBUG(@"Layout with animation enabled %d", [UIView areAnimationsEnabled]);

    CGRect nameTextFieldFrame = _nameTextField.frame;
    nameTextFieldFrame.size.width = nameTextFieldWidth;
    
    CGFloat usedHeight = targetPreviewSize.height + previewToLabelGap + nameTextFieldFrame.size.height;

    CGRect targetPreviewFrame;
    targetPreviewFrame.origin.x = floor(CGRectGetMidX(bounds) - targetPreviewSize.width / 2);
    targetPreviewFrame.origin.y = CGRectGetMinY(bounds) + floor((CGRectGetHeight(bounds) - usedHeight) / 2);
    targetPreviewFrame.size = targetPreviewSize;

    CGRect previewFrame;
    if (_textFieldEditing && !_textFieldIsEndingEditing) {
        RENAME_DEBUG(@"  ... editing mode");

        _picker.activeScrollView.alpha = 0;

        previewFrame = [_previewView fitPreviewRectInFrame:targetPreviewFrame];
        //NSLog(@"targetPreviewFrame = %@, previewFrame = %@", NSStringFromCGRect(targetPreviewFrame), NSStringFromCGRect(previewFrame));
        
        _nameTextField.alpha = 1;
    } else {
        RENAME_DEBUG(@"  ... not editing mode");

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
    nameTextFieldFrame.origin.x = floor(CGRectGetMidX(bounds) - nameTextFieldWidth / 2);
    nameTextFieldFrame.origin.y = CGRectGetMaxY(targetPreviewFrame) + previewToLabelGap;
    nameTextFieldFrame.size.width = nameTextFieldWidth;

    _nameTextField.frame = nameTextFieldFrame;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration;
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    [self _setupPreviewWithOrientation:toInterfaceOrientation];
}

- (void)_shieldViewTapped:(UIGestureRecognizer *)recognizer;
{
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self.shieldView removeFromSuperview];
        self.shieldView = nil;
        
        [self _done:nil];
    }
}

#pragma mark -
#pragma mark UITextField delegate

- (void)textFieldDidBeginEditing:(NSNotification *)note;
{
    RENAME_DEBUG(@"did begin editing");
    
    _textFieldEditing = YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
{
    RENAME_DEBUG(@"textFieldShouldEndEditing:");

    // We need an extra BOOL here to let us know we should really go ahead and end the rename.
    // The rename operation doesn't call our completion block until the file presenter queue has performed the -presentedItemDidMoveToURL:, but in that case the file item will have only updated its _filePresenterURL (which must update immediately and which can be accessed from any thead) and has only enqueued a main thread operation to update its _displayedFileURL (which is what sources the -name method below). The ordering of operations will still be correct since our completion block will still get called on the main thread after the display name is updated, but we can't tell that here.
    NSString *newName = [textField text];
    BOOL isSameName = [NSString isEmptyString:newName] || [newName isEqualToString:_fileItem.name];
    if (_isAttemptingRename || isSameName) {
        _textFieldIsEndingEditing = YES;
        
        if (isSameName) {
            // Unsolicited close of the keyboard (didn't tap the Done button, just pressed the close button on the software keyboard). We're done after this.
            _shouldSendFinishRenameAfterKeyboardResizes = YES;
            
            // The keyboard might not cause our view to resize if it is undocked/split. Our layout method is what animates the preview back into place, and importantly, puts the alpha back on the document picker's scroll view.
            [self.view setNeedsLayout];
        }
        
        // Make sure to remove the shield view.
        [self.shieldView removeFromSuperview];
        self.shieldView = nil;
        
        RENAME_DEBUG(@"Bail on empty/same name");
        return YES;
    }
    
    // Otherwise, start the rename and return NO for now, but remember that we've tried already.
    _isAttemptingRename = YES;
    NSURL *currentURL = [_fileItem.fileURL copy];
    
    NSString *uti = OFUTIForFileExtensionPreferringNative([currentURL pathExtension], NO);
    OBASSERT(uti);
    
    // We have no open documents at this point, so we don't need to synchronize with UIDocument autosaving via -performAsynchronousFileAccessUsingBlock:. We do want to prevent other documents from opening, though.
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    // We don't want a "directory changed" notification for the local documents directory.
    [_picker _beginIgnoringDocumentsDirectoryUpdates];
    
    [_fileItem.scope renameFileItem:_fileItem baseName:newName fileType:uti completionHandler:^(NSURL *destinationURL, NSError *error){
        
        [_picker _endIgnoringDocumentsDirectoryUpdates];
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        
        if (!destinationURL) {
            NSLog(@"Error renaming document with URL \"%@\" to \"%@\" with type \"%@\": %@", [currentURL absoluteString], newName, uti, [error toPropertyList]);
            OUI_PRESENT_ERROR(error);

            if ([error hasUnderlyingErrorDomain:OFSErrorDomain code:OFSFilenameAlreadyInUse]) {
                // Leave the fixed name for the user to try again.
                _isAttemptingRename = NO;
            } else {
                // Some other error which may not be correctable -- bail
                [self.view endEditing:YES];
            }
        } else {
            [_picker _didPerformRenameToFileURL:destinationURL];
            [self _done:nil];
        }
    }];
    
    return NO;
}

- (void)textFieldDidEndEditing:(NSNotification *)note;
{
    RENAME_DEBUG(@"did end editing, _receivedKeyboardWillResize:%d", _receivedKeyboardWillResize);
    RENAME_DEBUG(@"  _textFieldEditing %d", _textFieldEditing);
    RENAME_DEBUG(@"  _textFieldIsEndingEditing %d", _textFieldIsEndingEditing);
    RENAME_DEBUG(@"  _isAttemptingRename %d", _isAttemptingRename);
    RENAME_DEBUG(@"  _shouldSendFinishRenameAfterKeyboardResizes %d", _shouldSendFinishRenameAfterKeyboardResizes);
    
    _textFieldEditing = NO;
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
        [self _done:nil];
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    });
    
    return YES;
}

#pragma mark -
#pragma mark NSFilePresenter

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
            [self _cancel];
        }];
    }
}

- (void)presentedItemDidChange;
{
    // This gets spuriously sent after renames sometimes, but if there is an incoming edit from iCloud (or iTunes, once that works again), discard our rename.
    if (_isAttemptingRename == NO) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self _cancel];
        }];
    }
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

- (void)_setupPreviewWithOrientation:(UIInterfaceOrientation)orientation;
{
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    Class documentClass = [[OUIDocumentAppController controller] documentClassForURL:_fileItem.fileURL];
    
    _previewView.landscape = landscape;
    
    OUIDocumentPreview *preview = [OUIDocumentPreview makePreviewForDocumentClass:documentClass fileURL:_fileItem.fileURL date:_fileItem.fileModificationDate withLandscape:landscape];
    [_previewView discardPreviews];
    [_previewView addPreview:preview];
}

- (void)_cancel;
{
    RENAME_DEBUG(@"_cancel");

    // Clear the text field (which will be interpreted as leaving the name alone) and pretend the Done button was tapped
    _nameTextField.text = @"";
    [self _done:nil];
}

- (void)_done:(id)sender;
{
    // Let the keyboard drive the animation
    RENAME_DEBUG(@"-_done: calling -endEditing:");
    RENAME_DEBUG(@"  _isAttemptingRename %d", _receivedKeyboardWillResize);
    RENAME_DEBUG(@"  _receivedKeyboardWillResize %d", _receivedKeyboardWillResize);
    
    // Remove the shieldView
    [self.shieldView removeFromSuperview];
    self.shieldView = nil;

    // Make sure this isn't spuriously set by a software keyboard being toggled in/out with a hardware keyboard attached
    _receivedKeyboardWillResize = NO;

    BOOL rc = [self.view endEditing:NO];
    if (rc == NO && _isAttemptingRename) {
        // Our -textFieldShouldEndEditing: call rejected the edit so that we want wait to see if the rename actually worked before ending editing.
        RENAME_DEBUG(@"Rename is in progress -- waiting for it to finish or fail");
        return;
    }
    
    RENAME_DEBUG(@"-_done:, after -endEditing:...");
    RENAME_DEBUG(@"  _isAttemptingRename %d", _receivedKeyboardWillResize);
    RENAME_DEBUG(@"  _receivedKeyboardWillResize %d", _receivedKeyboardWillResize);

    if (_receivedKeyboardWillResize == NO) {
        // If we are renaming and there is no keyboard visibile, we are using a hardware keyboard -- we won't get notified of the keyboard hiding and it can't control the animation, so we must do it ourselves
        // Switched from OUIAnimationSequence to ensure that the call to _finishRenameAfterHidingKeyboard happens outside of a [UIView animateWithDuration:...] call as it was inside of OUIAnimationSequence. This was causing odd animations when -willMoveToParentViewController was calling -setItems:animated: on _picker.toolbar. This way we can take advantage of the default crossfade animation that we get for free. 
        [UIView animateWithDuration:_animationDuration animations:^{
            [UIView setAnimationCurve:_animationCurve];
            [self _prepareToResizeWithDuration:_animationDuration curve:_animationCurve];
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            [self _finishRenameAfterHidingKeyboard];
        }];
    } else {
        // We need to wait until the animation is done to finish the rename.
        _shouldSendFinishRenameAfterKeyboardResizes = YES;
        RENAME_DEBUG(@"-_done: Set _shouldSendFinishRenameAfterKeyboardResizes");
    }
}

- (void)_prepareToResizeWithDuration:(NSTimeInterval)animationInterval curve:(UIViewAnimationCurve)animationCurve;
{
    RENAME_DEBUG(@"_prepareToResizeWithDuration:%f curve:%d", animationInterval, animationCurve);

    _animationDuration = animationInterval;
    _animationCurve = animationCurve;
    
    _previewView.animationDuration = animationInterval;
    _previewView.animationCurve = animationCurve;
}

- (void)_finishRenameAfterHidingKeyboard;
{
    RENAME_DEBUG(@"_finishRenameAfterHidingKeyboard");

    OBPRECONDITION(_textFieldEditing == NO);
    
    OBASSERT(_isRegisteredAsFilePresenter);
    if (_isRegisteredAsFilePresenter) {
        _isRegisteredAsFilePresenter = NO;
        [NSFileCoordinator removeFilePresenter:self];
    }
    
    // Unhide the preview view we hid above
    OUIWithoutAnimating(^{
        OBASSERT(_renamingFileItemView);
        OBASSERT(_renamingFileItemView.renaming);
        _renamingFileItemView.renaming = NO;
        
        _renamingFileItemView = nil;
    });
    
    // We should have restored this already, but the user will be locked out if some keyboard animstion snafu prevents our layout from doing it.
    OBASSERT(_picker.activeScrollView.alpha == 1);
    _picker.activeScrollView.alpha = 1;
    
    RENAME_DEBUG(@"Calling _didStopRenamingFileItem");
    [_picker _didStopRenamingFileItem];
}

- (void)_didBeginResizingForKeyboard:(NSNotification *)note;
{
    RENAME_DEBUG(@"_didBeginResizingForKeyboard: %@", note);

    // Note that the keyboard is going to drive this animation
    _receivedKeyboardWillResize = YES;
    
    [self.view setNeedsLayout];
    
    NSDictionary *originalInfo = [[note userInfo] objectForKey:OUIMainViewControllerResizedForKeyboardOriginalUserInfoKey];
    NSNumber *duration = [originalInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey];
    NSNumber *curve = [originalInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey];
    
    OBASSERT(duration);
    OBASSERT(curve);
  
    [self _prepareToResizeWithDuration:[duration doubleValue] curve:[curve intValue]];
}

- (void)_didFinishResizingForKeyboard:(NSNotification *)note;
{
    RENAME_DEBUG(@"_didFinishResizingForKeyboard: %@", note);
    
    if (_shouldSendFinishRenameAfterKeyboardResizes) {
        // The keyboard drove the animation and now it is done.
        [self _finishRenameAfterHidingKeyboard];
    }
    
    // Reset this in case the user is just toggling the hardware keyboard while editing.
    _receivedKeyboardWillResize = NO;
}

@end
