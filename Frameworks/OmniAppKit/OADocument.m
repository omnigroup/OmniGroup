// Copyright 2003-2017, 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OADocument.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/OAStrings.h>
#import <OmniBase/rcsid.h>

@implementation OADocument
{
    NSString *_scriptIdentifier;
    NSScriptObjectSpecifier *_objectSpecifier;

    struct {
        unsigned int isInsideApplicationWrapper:1;
    } _oaFlags;
}

- (void)dealloc;
{
    [_scriptIdentifier release];
    [_objectSpecifier release];
    [super dealloc];
}

+ (BOOL)isFileURLInApplicationWrapper:(NSURL *)fileURL;
{
    return [[[fileURL path] stringByStandardizingPath] hasPrefix:[[[NSBundle mainBundle] bundlePath] stringByStandardizingPath]];
}

- (BOOL)isInsideApplicationWrapper;
{
    return _oaFlags.isInsideApplicationWrapper;
}

#pragma mark - AppleScript

- (NSString *)scriptIdentifier;
{
    while (!_scriptIdentifier || [[OAApplication sharedApplication] valueInOrderedDocumentsWithUniqueID:_scriptIdentifier ignoringDocument:self]) {
        [_scriptIdentifier release];
        _scriptIdentifier = OFXMLCreateID();
    }
    return _scriptIdentifier;
}

- (NSString *)scriptIdentifierIfSet;
{
    return _scriptIdentifier;
}

- (NSScriptObjectSpecifier *)objectSpecifier
{
    if (_objectSpecifier)
        return _objectSpecifier;
    
    NSScriptClassDescription *desc = [NSScriptClassDescription classDescriptionForClass:[[OAApplication sharedApplication] class]];
    _objectSpecifier = [[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:desc
                                                                   containerSpecifier:nil
                                                                                  key:@"orderedDocuments"
                                                                             uniqueID:self.scriptIdentifier];
    return _objectSpecifier;
}

- (void)canCloseDocument:(void (^)(BOOL shouldClose))completion;
{
#if MAC_APP_STORE_RETAIL_DEMO
    completion(YES); // Retail demos can close their documents without saving
#else
    completion = [[completion copy] autorelease];
    OBStrongRetain(completion); // Doing this so later conversion to ARC doesn't fool us into getting rid of the retain-until-called hack.
    [super canCloseDocumentWithDelegate:self shouldCloseSelector:@selector(_oa_document:shouldClose:contextInfo:) contextInfo:completion];
#endif
}

- (void)_oa_document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo;
{
    OBPRECONDITION(contextInfo);
    
    if (contextInfo) {
        void (^completion)(BOOL shouldClose) = (typeof(completion))contextInfo;
        OBAutorelease(completion);
        
        completion(shouldClose);
    }
}

#pragma mark - NSDocument subclass

- (void)setFileURL:(NSURL *)fileURL;
{
    _oaFlags.isInsideApplicationWrapper = [self.class isFileURLInApplicationWrapper:fileURL];
    [super setFileURL:fileURL];
}

// Support the concept of auxiliary window controllers, which should not keep the document open. Closing the last non-auxiliary window controller should close the document. This differs from setting `shouldCloseDocument` on the window controller always since we might want to support multiple non-auxiliary window controllers. Closing one of those shouldn't force the document to close.
- (void)shouldCloseWindowController:(NSWindowController *)windowController delegate:(nullable id)delegate shouldCloseSelector:(nullable SEL)shouldCloseSelector contextInfo:(nullable void *)contextInfo;
{
    NSArray <NSWindowController *> *windowControllers = self.windowControllers;
    OBASSERT([windowControllers containsObjectIdenticalTo:windowController]);

    // None of this is relevant unless we have more than one window controller.
    if ([windowControllers count] > 1) {
        BOOL hasOtherMainWindowController = [windowControllers any:^BOOL(NSWindowController *candidate) {
            return (candidate != windowController) && !candidate.auxiliary;
        }];

        if (!hasOtherMainWindowController) {
            // This is the simplest way to initiate a close of the document, but we are grabbing ownership of this flag as noted in the comment for -isAuxiliary
            windowController.shouldCloseDocument = YES;
        } else {
            // Clear the flag -- if the document was dirty and a save sheet was cancelled, we don't want to leave the flag on. Another main window controller could be created, and the old one closed again, leading to the document being spuriously closed.
            for (NSWindowController *wc in windowControllers) {
                wc.shouldCloseDocument = NO;
            }
        }
    }

    [super shouldCloseWindowController:windowController delegate:delegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
}

- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)shouldCloseSelector contextInfo:(void *)contextInfo;
{
    void (^completion)(BOOL) = ^(BOOL shouldClose){
        // - (void)document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo;
        void (*imp)(id, SEL, id, BOOL, void *) = (typeof(imp))objc_msgSend;
        imp(delegate, shouldCloseSelector, self, shouldClose, contextInfo);
    };
    
    [self canCloseDocument:completion];
}

- (BOOL)isInViewingMode;
{
    if (self.isInsideApplicationWrapper)
        return YES;

    return [super isInViewingMode];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem;
{
    SEL action = [anItem action];
    if (action == @selector(renameDocument:)
        || action == @selector(saveDocument:)
        || action == @selector(lockDocument:)
        || action == @selector(unlockDocument:)
        || action == @selector(moveDocument:)) {
        return !(self.isInsideApplicationWrapper) && [super validateUserInterfaceItem:anItem];
    } else {
        return [super validateUserInterfaceItem:anItem];
    }
}

- (void)lockWithCompletionHandler:(void (^)(NSError *))completionHandler;
{
    if (self.isInsideApplicationWrapper) {
        NSError *error = nil;

        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to lock document.", @"OmniAppKit", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Cannot lock a document inside the application package.", @"OmniAppKit", OMNI_BUNDLE, @"error message");
        _OBError(&error, [OMNI_BUNDLE bundleIdentifier], 1, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (reason), nil);

        completionHandler(error);
    } else
        [super lockWithCompletionHandler:completionHandler];
}

- (void)lockDocumentWithCompletionHandler:(void (^)(BOOL))completionHandler;
{
    if (self.isInsideApplicationWrapper)
        completionHandler(NO);
    else
        [super lockDocumentWithCompletionHandler:completionHandler];
}

- (void)unlockWithCompletionHandler:(void (^)(NSError *))completionHandler;
{
    if (self.isInsideApplicationWrapper) {
        NSError *error = nil;

        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to unlock document.", @"OmniAppKit", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Cannot unlock a document inside the application package.", @"OmniAppKit", OMNI_BUNDLE, @"error message");
        _OBError(&error, [OMNI_BUNDLE bundleIdentifier], 1, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (reason), nil);

        completionHandler(error);
    } else
        [super unlockWithCompletionHandler:completionHandler];
}

- (void)unlockDocumentWithCompletionHandler:(void (^)(BOOL))completionHandler;
{
    if (self.isInsideApplicationWrapper)
        completionHandler(NO);
    else
        [super unlockDocumentWithCompletionHandler:completionHandler];
}

- (void)moveDocumentWithCompletionHandler:(void (^)(BOOL))completionHandler;
{
    if (self.isInsideApplicationWrapper)
        completionHandler(NO);
    else
        [super moveDocumentWithCompletionHandler:completionHandler];
}

- (void)moveToURL:(NSURL *)url completionHandler:(void (^)(NSError *))completionHandler;
{
    NSError *error = nil;
    if (!([self canMoveToURL:url error:&error])) {
        completionHandler(error);
        return;
    }

    [super moveToURL:url completionHandler:completionHandler];
}

#pragma mark - OADocumentSubclass category

- (BOOL)canSaveToURL:(NSURL *)url error:(NSError **)error;
{
#if MAC_APP_STORE_RETAIL_DEMO
    NSString *description = OAFeatureNotEnabledForThisDemo();
    NSString *reason = nil;
    _OBError(error, [OMNI_BUNDLE bundleIdentifier], 1, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (reason), nil);
    return NO;
#else
    if ([self.class isFileURLInApplicationWrapper:url]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save document.", @"OmniAppKit", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Documents cannot be saved inside the application package.", @"OmniAppKit", OMNI_BUNDLE, @"error message");
        _OBError(error, [OMNI_BUNDLE bundleIdentifier], 1, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (reason), nil);

        return NO;
    }
    return YES;
#endif
}

- (BOOL)canMoveToURL:(NSURL *)url error:(NSError **)error;
{
#if MAC_APP_STORE_RETAIL_DEMO
    NSString *description = OAFeatureNotEnabledForThisDemo();
    NSString *reason = nil;
    _OBError(error, [OMNI_BUNDLE bundleIdentifier], 1, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (reason), nil);
    return NO;
#else
    if ([self.class isFileURLInApplicationWrapper:url]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to move document.", @"OmniAppKit", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Documents cannot be moved inside the application package.", @"OmniAppKit", OMNI_BUNDLE, @"error message");
        _OBError(error, [OMNI_BUNDLE bundleIdentifier], 1, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (reason), nil);

        return NO;
    }
    return YES;
#endif
}

@end


@implementation NSWindowController (OADocumentExtensions)

- (BOOL)isAuxiliary;
{
    return NO;
}

@end
