// Copyright 2015-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@import Foundation;
@import OmniUnzip;

#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIExportOptionsType.h>
#import <OmniUI/OUIAppController.h>

NS_ASSUME_NONNULL_BEGIN

/// Create instances using the +exporter method instead of -init
@interface OUIDocumentExporter : NSObject

+ (instancetype)exporter;

- (instancetype)init NS_UNAVAILABLE;

- (UIBarButtonItem *)makeExportBarButtonItemWithTarget:(id)target action:(SEL)action forViewController:(UIViewController *)viewController;
- (void)exportDocument:(OUIDocument *)document fromViewController:(UIViewController *)parentViewController barButtonItem:(UIBarButtonItem *)exportBarButtonItem;

@property(nonatomic,readonly) NSArray <UIActivity *> *supportedActivities;

- (NSArray *)availableExportTypesForFileURL:(NSURL *)fileURL;

#pragma mark - Possible Subclass Overrides

- (nullable UIImage *)iconForUTI:(NSString *)fileUTI;
- (nullable UIImage *)exportIconForUTI:(NSString *)fileUTI;
- (nullable NSString *)exportLabelForUTI:(NSString *)fileUTI;

// UIActivity images
@property(class,readonly,nonatomic) UIImage *sendToPasteboardImage;
@property(class,readonly,nonatomic) UIImage *copyAsImageImage NS_RETURNS_NOT_RETAINED;
@property(class,readonly,nonatomic) UIImage *sendToPhotosImage;


- (NSArray *)availableInAppPurchaseExportTypesForFileURL:(NSURL *)fileURL;
- (void)purchaseExportType:(NSString *)fileUTI scene:(UIScene *)scene;
- (NSString *)purchaseDescriptionForExportType:(NSString *)fileUTI;

@end

// If subclassed, these will be called on already opened document instances
@interface OUIDocument (OUIDocumentExporter)
- (nullable NSData *)PNGData:(NSError **)outError;
- (nullable UIImage *)cameraRolImage:(NSError **)outError;
- (void)printWithParentViewController:(UIViewController *)parentViewController completionHandler:(void (^)(NSError * _Nullable errorOrNil))completionHandler;
- (void)exportFileWrapperOfType:(NSString *)exportType parentViewController:(UIViewController *)parentViewController withCompletionHandler:(void (^)(NSFileWrapper * _Nullable fileWrapper, NSError * _Nullable error))completionHandler;
@end

NS_ASSUME_NONNULL_END
