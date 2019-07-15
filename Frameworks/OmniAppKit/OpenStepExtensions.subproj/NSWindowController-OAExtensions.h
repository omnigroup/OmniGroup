// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSWindowController.h>

#import <AppKit/NSCell.h> // For NSControlSize

NS_ASSUME_NONNULL_BEGIN

@interface NSWindowController (OAExtensions)

+ (nullable NSWindow *)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize;
+ (void)startingLongOperation:(NSString *)operationDescription controlSize:(NSControlSize)controlSize inWindow:(NSWindow *)documentWindow automaticallyEnds:(BOOL)shouldAutomaticallyEnd;
+ (void)continuingLongOperation:(NSString *)operationStatus;
+ (void)finishedLongOperationForWindow:(NSWindow *)window;
+ (void)finishedLongOperation;

- (void)startingLongOperation:(NSString *)operationDescription;

@end

#pragma mark -

@interface NSObject (OALongOperationIndicatorApplicationDelegate)

- (BOOL)shouldShowLongOperationIndicatorForWindow:(nullable NSWindow *)window;

@end

#pragma mark -

@protocol OAMetadataTracking

- (BOOL)hasUnsavedMetadata;
- (void)metadataChanged;
- (void)clearMetadataChanges;

@end

NS_ASSUME_NONNULL_END
