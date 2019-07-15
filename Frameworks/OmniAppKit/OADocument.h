// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSDocument.h>

@interface OADocument : NSDocument

// We use 'id' based object specifiers.
@property(nonatomic,readonly) NSString *scriptIdentifier;
@property(nonatomic,readonly) NSString *scriptIdentifierIfSet;

+ (BOOL)isFileURLInApplicationWrapper:(NSURL *)fileURL;
- (BOOL)isInsideApplicationWrapper;

// Block-based version of -canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo:.
- (void)canCloseDocument:(void (^)(BOOL shouldClose))completion;

@end

@interface NSWindowController (OADocumentExtensions)

// If set, then this window controller will be ignored for the purposes of deciding whether to close the document when another window controller is closed. Defaults to NO. If you subclass to return YES, note that your 'main' window controllers will have their `shouldCloseDocument` property modified.
@property(nonatomic,readonly,getter=isAuxiliary) BOOL auxiliary;

@end
