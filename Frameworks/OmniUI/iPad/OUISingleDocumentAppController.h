// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIUndoBarButtonItem.h>

@class OUIDocument, OUIToolbarViewController;

@interface OUISingleDocumentAppController : OUIAppController <UITextFieldDelegate, OUIUndoBarButtonItemTarget>
{
@private
    
    UIWindow *_window;
    OUIToolbarViewController *_toolbarViewController;
    
    UIBarButtonItem *_appTitleToolbarItem;
    UITextField *_appTitleToolbarTextField;
    
    UIBarButtonItem *_closeDocumentBarButtonItem;
    UITextField *_documentTitleTextField;
    UIBarButtonItem *_documentTitleToolbarItem;
    OUIUndoBarButtonItem *_undoBarButtonItem;
    UIBarButtonItem *_infoBarButtonItem;
    OUIDocument *_document;
    
    BOOL _openAnimated;
}

@property(nonatomic,retain) IBOutlet UIWindow *window;
@property(nonatomic,retain) IBOutlet OUIToolbarViewController *toolbarViewController;
@property(nonatomic,retain) IBOutlet UIBarButtonItem *appTitleToolbarItem;
@property(nonatomic,retain) IBOutlet UITextField *appTitleToolbarTextField;
@property(nonatomic,retain) IBOutlet UITextField *documentTitleTextField;
@property(nonatomic,retain) IBOutlet UIBarButtonItem *documentTitleToolbarItem;

@property(readonly) UIBarButtonItem *closeDocumentBarButtonItem;
@property(readonly) OUIUndoBarButtonItem *undoBarButtonItem;
@property(readonly) UIBarButtonItem *infoBarButtonItem;

- (NSString *)documentTypeForURL:(NSURL *)url;
- (id <OUIDocument>)createNewDocumentAtURL:(NSURL *)url error:(NSError **)outError;
- (IBAction)makeNewDocument:(id)sender;

@property(readonly) OUIDocument *document;

// Subclass responsibility
- (Class)documentClassForURL:(NSURL *)url;
- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;
- (void)dismissInspectorImmediately;

@end
