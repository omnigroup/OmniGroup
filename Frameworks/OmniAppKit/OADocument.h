// Copyright 2003-2005, 2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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
