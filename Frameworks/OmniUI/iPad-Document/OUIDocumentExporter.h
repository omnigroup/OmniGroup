// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@import Foundation;
@import OmniDocumentStore;
@import OmniUnzip;

#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIExportOptionsType.h>
#import <OmniUI/OUIAppController.h>

NS_ASSUME_NONNULL_BEGIN

OB_DEPRECATED_ATTRIBUTE
@protocol OUIDocumentExporterHost <NSObject>

@optional
- (NSURL *)fileURLToExport OB_DEPRECATED_ATTRIBUTE;

- (UIColor *)tintColorForExportMenu OB_DEPRECATED_ATTRIBUTE; // use [UIColor blackColor] to also get untemplated images
- (void)prepareToExport OB_DEPRECATED_ATTRIBUTE;
- (NSArray <NSURL *> *)fileURLsToExport;

- (NSArray *)fileItemsToExport OB_DEPRECATED_ATTRIBUTE;
- (ODSFileItem *)fileItemToExport OB_DEPRECATED_ATTRIBUTE;

@end

/// Create instances using the +exporter method instead of -init
@interface OUIDocumentExporter : NSObject

+ (instancetype)exporter;

- (instancetype)init NS_UNAVAILABLE;

- (UIBarButtonItem *)makeExportBarButtonItemWithTarget:(id)target action:(SEL)action forViewController:(UIViewController *)viewController;
- (void)exportDocument:(OUIDocument *)document fromViewController:(UIViewController *)parentViewController barButtonItem:(nullable UIBarButtonItem *)exportBarButtonItem;

@property(nonatomic,readonly) NSArray <UIActivity *> *supportedActivities;

- (NSArray *)availableExportTypesForFileURL:(NSURL *)fileURL;

#pragma mark - Possible Subclass Overrides

- (UIImage *)iconForUTI:(NSString *)fileUTI;
- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
- (NSString *)exportLabelForUTI:(NSString *)fileUTI;

// UIActivity images
@property(class,readonly,nonatomic) UIImage *sendToPasteboardImage;
@property(class,readonly,nonatomic) UIImage *copyAsImageImage NS_RETURNS_NOT_RETAINED;
@property(class,readonly,nonatomic) UIImage *sendToPhotosImage;
@property(class,readonly,nonatomic) UIImage *printImage;


- (NSArray *)availableInAppPurchaseExportTypesForFileURL:(NSURL *)fileURL;
- (void)purchaseExportType:(NSString *)fileUTI navigationController:(UINavigationController *)navigationController;  // not sure we should really have the navigation controller here.  it might need to just be generic view controller (our hostController).  also, it might turn out this can be implemented on the superclass instead of the subclasses.
- (NSString *)purchaseDescriptionForExportType:(NSString *)fileUTI;

@end

// If subclassed, these will be called on already opened document instances
@interface OUIDocument (OUIDocumentExporter)
- (nullable NSData *)PNGData:(NSError **)outError;
- (nullable UIImage *)cameraRolImage:(NSError **)outError;
- (void)printWithParentViewController:(UIViewController *)parentViewController completionHandler:(void (^)(NSError * _Nullable errorOrNil))completionHandler;
- (void)exportFileWrapperOfType:(NSString *)exportType parentViewController:(UIViewController *)parentViewController withCompletionHandler:(void (^)(NSFileWrapper * _Nullable fileWrapper, NSError * _Nullable error))completionHandler;
@end

@class OFXServerAccount;
@interface OUIDocumentExporter (OUIDocumentExporterDeprecated)
// Subclass -[ODSFileItem(OUIDocumentExtensions) availableExportTypesForFileExportToLocalDocuments:] instead.
- (NSArray *)appSpecificAvailableExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType OB_DEPRECATED_ATTRIBUTE;

// Use UIActivity/NSURL-based API.
- (BOOL)canExportFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;
- (void)exportItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;
- (void)exportItem:(ODSFileItem *)fileItem sender:(id)sender OB_DEPRECATED_ATTRIBUTE;
- (void)emailFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;
- (nullable NSData *)copyAsImageDataForFileURL:(NSURL *)fileURL error:(NSError **)outError OB_DEPRECATED_ATTRIBUTE;
- (NSArray *)availableExportTypesForFileItem:(ODSFileItem *)fileItem exportOptionsType:(OUIExportOptionsType)exportOptionsType OB_DEPRECATED_ATTRIBUTE;
- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(ODSFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper * _Nullable fileWrapper, NSError * _Nullable error))completionHandler OB_DEPRECATED_ATTRIBUTE;
- (nullable NSArray<OUIMenuOption *> *)additionalExportOptionsForFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;
- (NSArray *)availableInAppPurchaseExportTypesForFileItem:(ODSFileItem *)fileItem exportOptionsType:(OUIExportOptionsType)exportOptionsType OB_DEPRECATED_ATTRIBUTE;
- (NSString *)printButtonTitleForFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;
- (void)printFileItem:(ODSFileItem *)fileItem fromButton:(UIBarButtonItem *)aButton OB_DEPRECATED_ATTRIBUTE;
- (nullable NSData *)copyAsImageDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError OB_DEPRECATED_ATTRIBUTE;
- (UIImage *)cameraRollImageForFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;
- (nullable NSData *)PDFDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)error OB_DEPRECATED_ATTRIBUTE;
- (nullable NSData *)PNGDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)error OB_DEPRECATED_ATTRIBUTE;

// Indicate what types are supported by subclassing +[OUIDocument availableExportTypesForFileType:] or by subclassing -PNGData:, etc.
- (BOOL)supportsExportAsPNG OB_DEPRECATED_ATTRIBUTE;
- (BOOL)supportsCopyAsImage OB_DEPRECATED_ATTRIBUTE;
- (BOOL)supportsSendToCameraRoll OB_DEPRECATED_ATTRIBUTE;
- (BOOL)supportsPrinting OB_DEPRECATED_ATTRIBUTE;
- (UIImage *)cameraRollImageForFileURL:(NSURL *)fileURL OB_DEPRECATED_ATTRIBUTE;
- (BOOL)supportsExportAsPDF OB_DEPRECATED_ATTRIBUTE;

// Temporary on a work-in-progress branch.
- (nullable NSArray<OUIMenuOption *> *)additionalExportOptionsForFileURL:(NSURL *)fileURL OB_DEPRECATED_ATTRIBUTE;
- (nullable NSData *)PDFDataForFileURL:(NSURL *)fileURL error:(NSError **)error OB_DEPRECATED_ATTRIBUTE;
- (nullable NSData *)PNGDataForFileURL:(NSURL *)fileURL error:(NSError **)error OB_DEPRECATED_ATTRIBUTE;
- (void)printFileURL:(NSURL *)fileURL fromButton:(UIBarButtonItem *)aButton OB_DEPRECATED_ATTRIBUTE;
- (void)exportFileWrapperOfType:(NSString *)exportType forFileURL:(NSURL *)fileURL withCompletionHandler:(void (^)(NSFileWrapper * _Nullable fileWrapper, NSError * _Nullable error))completionHandler OB_DEPRECATED_ATTRIBUTE;
- (void)generatePDFDataForFileURL:(NSURL *)fileURL completionHandler:(void (^)(NSData * _Nullable data, NSError * _Nullable errorOrNil))completionHandler OB_DEPRECATED_ATTRIBUTE;

@end

NS_ASSUME_NONNULL_END

