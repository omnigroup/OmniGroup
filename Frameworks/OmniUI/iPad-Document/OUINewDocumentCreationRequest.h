// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUITemplatePickerDelegate.h>

NS_ASSUME_NONNULL_BEGIN

@class OUINewDocumentCreationRequest;
@protocol OUIInternalTemplateDelegate, OUITemplatePickerDelegate;

@protocol OUIDocumentCreationRequestDelegate <NSObject>

@optional

- (NSString *)documentCreationRequestDocumentTypeForNewFiles:(nullable OUINewDocumentCreationRequest *)request;
- (NSArray *)documentCreationRequestEditableDocumentTypes:(nullable OUINewDocumentCreationRequest *)request;
- (NSArray<NSString *> *)templateUTIs;

@end

@interface OUINewDocumentCreationRequest : NSObject <OUITemplatePickerDelegate>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDelegate:(id <OUIDocumentCreationRequestDelegate>)delegate viewController:(UIViewController *)parentViewController creationHandler:(void(^)(NSURL *_Nullable urlToImport, UIDocumentBrowserImportMode importMode))creationHandler NS_DESIGNATED_INITIALIZER;

// This will present a template picker if the delegate calls for it, otherwise it will create a new untitled document.
- (void)runWithInternalTemplateDelegate:(nullable id <OUIInternalTemplateDelegate>)internalTemplateDelegate;

@property(nullable,readonly,nonatomic) NSString *documentTypeForNewFiles;
- (nullable NSURL *)temporaryURLForCreatingNewDocumentNamed:(nullable NSString *)documentName;

@end

NS_ASSUME_NONNULL_END

