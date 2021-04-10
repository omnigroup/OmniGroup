// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSStore.h>
#import <OmniUIDocument/OUITemplatePickerDelegate.h>

NS_ASSUME_NONNULL_BEGIN

@class OUINewDocumentCreationContext;
@class OUINewDocumentCreationRequest;
@protocol OUIInternalTemplateDelegate, OUITemplatePickerDelegate;

@protocol OUIDocumentCreationRequestDelegate <NSObject>

@optional

- (NSString *)documentCreationRequest:(OUINewDocumentCreationRequest *)request documentTypeForNewFilesOfType:(ODSDocumentType)type;

- (NSString *)documentCreationRequestDocumentTypeForNewFiles:(OUINewDocumentCreationRequest *)request;
- (NSString *)documentCreationRequestDocumentTypeForNewTemplateFiles:(OUINewDocumentCreationRequest *)request;
- (NSString *)documentCreationRequestDocumentTypeForNewOtherFiles:(OUINewDocumentCreationRequest *)request;
- (NSArray *)documentCreationRequestEditableDocumentTypes:(OUINewDocumentCreationRequest *)request;

@end

@interface OUINewDocumentCreationRequest : NSObject <OUITemplatePickerDelegate>

- init NS_UNAVAILABLE;
- initWithDelegate:(id <OUIDocumentCreationRequestDelegate>)delegate creationHandler:(void(^)(NSURL *_Nullable urlToImport, UIDocumentBrowserImportMode importMode))creationHandler NS_DESIGNATED_INITIALIZER;

// This will present a template picker if the delegate calls for it, otherwise it will create a new untitled document.
// There are two flavors of template pickers.  If the documentPicker has an internalTemplateDelegate set it will use the new template picker which supports displaying of internal templates to the app wrapper, without the need to copy them out.
// Othrwise, if the documentPicker's delegate has implemented, documentPickerTemplateDocumentFilter:, you will end up with the old style template picker.
- (void)runWithViewController:(UIViewController *)parentViewController internalTemplateDelegate:(nullable id <OUIInternalTemplateDelegate>)internalTemplateDelegate;

// The new prefered way to create a new document is to use the templateContext.  The other newDocumentWithTemplateFileItem: functions will create a templateContext and then call newDocumentWithTemplateContext:
- (void)newDocumentWithContext:(OUINewDocumentCreationContext *)context completion:(void (^ _Nullable)(void))completion;
//- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem documentType:(ODSDocumentType)type preserveDocumentName:(BOOL)preserveDocumentName completion:(void (^)(void))completion;
//- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem documentType:(ODSDocumentType)type completion:(void (^ _Nullable)(void))completion;
//- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem;

@property(readonly,nonatomic) NSString *documentTypeForNewFiles;
- (nullable NSString *)documentTypeForNewFilesOfType:(ODSDocumentType)type;
- (NSURL *)temporaryURLForCreatingNewDocumentNamed:(NSString *)documentName withType:(ODSDocumentType)type;

@end

NS_ASSUME_NONNULL_END

