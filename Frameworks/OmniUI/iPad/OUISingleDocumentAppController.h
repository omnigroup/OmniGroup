// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIUndoBarButtonItem.h>

@class OUIDocument, OUIToolbarViewController, OUIBarButtonItem;

@interface OUISingleDocumentAppController : OUIAppController <UITextFieldDelegate, OUIUndoBarButtonItemTarget>
{
@private
    
    UIWindow *_window;
    OUIToolbarViewController *_toolbarViewController;
    
    // UIBarButtonItem *_appTitleToolbarItem;
    UIButton *_appTitleToolbarButton;
    
    OUIBarButtonItem *_closeDocumentBarButtonItem;
    UITextField *_documentTitleTextField;
    UIBarButtonItem *_documentTitleToolbarItem;
    OUIUndoBarButtonItem *_undoBarButtonItem;
    OUIBarButtonItem *_infoBarButtonItem;
    OUIDocument *_document;
    
    BOOL _openAnimated;
}

@property(nonatomic,retain) IBOutlet UIWindow *window;
@property(nonatomic,retain) IBOutlet OUIToolbarViewController *toolbarViewController;
@property(nonatomic,retain) IBOutlet UITextField *documentTitleTextField;
@property(nonatomic,retain) IBOutlet UIBarButtonItem *documentTitleToolbarItem;

@property(nonatomic,retain) UIButton *appTitleToolbarButton;
@property(readonly) OUIBarButtonItem *closeDocumentBarButtonItem;
@property(readonly) OUIUndoBarButtonItem *undoBarButtonItem;
@property(readonly) OUIBarButtonItem *infoBarButtonItem;

- (NSString *)documentTypeForURL:(NSURL *)url;
- (BOOL)createNewDocumentAtURL:(NSURL *)url error:(NSError **)outError;
- (IBAction)makeNewDocument:(id)sender;

@property(readonly) OUIDocument *document;

// UIApplicationDelegate methods we implement (see OUIAppController too)
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;
- (void)applicationDidEnterBackground:(UIApplication *)application;

// Subclass responsibility
- (Class)documentClassForURL:(NSURL *)url;
- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;

@end
