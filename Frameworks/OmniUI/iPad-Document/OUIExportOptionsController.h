// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <UIKit/UINavigationController.h>

#import <OmniUIDocument/OUIExportOptionsType.h>

@class OUIDocumentExporter;

NS_ASSUME_NONNULL_BEGIN

@interface OUIExportOptionsController : NSObject

- (id)initWithFileURLs:(NSArray <NSURL *> *)fileURLs exporter:(OUIDocumentExporter *)exporter activity:(UIActivity *)activity NS_DESIGNATED_INITIALIZER;
- (id)init NS_UNAVAILABLE;

- (BOOL)hasExportOptions;

@property(nonatomic,readonly) UIViewController *viewController;

@end

NS_ASSUME_NONNULL_END

