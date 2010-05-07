// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <OmniUI/OUIDocumentPickerView.h>

@class OFSetBinding;
@class OUIDocumentProxy, OUIDocumentPickerView;
@protocol OUIDocumentPickerDelegate;

@interface OUIDocumentPicker : UIViewController <UIGestureRecognizerDelegate, OUIDocumentPickerViewDelegate, UIDocumentInteractionControllerDelegate>
{
@private
    id <OUIDocumentPickerDelegate> _nonretained_delegate;
    
    OUIDocumentPickerView *_previewScrollView;
    UILabel *_titleLabel;
    UILabel *_dateLabel;
    UIView *_buttonGroupView;
    UIButton *_favoriteButton;
    UIButton *_exportButton;
    UIButton *_newDocumentButton;
    UIButton *_deleteButton;
    
    NSString *_directory;
    NSSet *_proxies;
    OFSetBinding *_proxiesBinding;
    id _proxyTappedTarget;
    SEL _proxyTappedAction;
    NSMutableArray *_actionSheetActions;
    
    OUIDocumentProxy *_selectedProxyBeforeOrientationChange;
    
    UIActionSheet *_nonretainedActionSheet;
}

+ (NSString *)userDocumentsDirectory;
+ (NSString *)sampleDocumentsDirectory;
+ (void)copySampleDocumentsToUserDocuments;

+ (NSString *)pathToSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;
+ (NSString *)availablePathInDirectory:(NSString *)dir baseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
- (OUIDocumentProxy *)proxyByInstantiatingSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;

@property(assign,nonatomic) IBOutlet id <OUIDocumentPickerDelegate> delegate;

@property(retain) IBOutlet OUIDocumentPickerView *previewScrollView;
@property(retain) IBOutlet UILabel *titleLabel;
@property(retain) IBOutlet UILabel *dateLabel;
@property(retain) IBOutlet UIView *buttonGroupView;
@property(retain) IBOutlet UIButton *favoriteButton;
@property(retain) IBOutlet UIButton *exportButton;
@property(retain) IBOutlet UIButton *newDocumentButton;
@property(retain) IBOutlet UIButton *deleteButton;

@property(copy,nonatomic) NSString *directory;
@property(retain) id proxyTappedTarget;
@property(assign) SEL proxyTappedAction;

- (void)rescanDocuments;
- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL;
- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL animated:(BOOL)animated;
- (BOOL)hasDocuments;

- (OUIDocumentProxy *)revealAndActivateNewDocumentAtURL:(NSURL *)newDocumentURL;

- (OUIDocumentProxy *)selectedProxy;
- (OUIDocumentProxy *)proxyWithURL:(NSURL *)url;
- (OUIDocumentProxy *)proxyNamed:(NSString *)documentName;
- (BOOL)canEditProxy:(OUIDocumentProxy *)proxy;
- (BOOL)deleteDocumentWithoutPrompt:(OUIDocumentProxy *)proxy error:(NSError **)outError;
- (OUIDocumentProxy *)renameProxy:(OUIDocumentProxy *)proxy toName:(NSString *)name type:(NSString *)documentUTI;

- (NSURL *)urlForNewDocumentOfType:(NSString *)documentUTI;
- (NSURL *)urlForNewDocumentWithName:(NSString *)name ofType:(NSString *)documentUTI;

- (void)scrollToProxy:(OUIDocumentProxy *)proxy animated:(BOOL)animated;

- (IBAction)favorite:(id)sender;
- (IBAction)newDocumentMenu:(id)sender;
- (IBAction)newDocument:(id)sender;
- (IBAction)duplicateDocument:(id)sender;
- (IBAction)delete:(id)sender;
- (IBAction)export:(id)sender;
- (IBAction)emailDocument:(id)sender;

@end
