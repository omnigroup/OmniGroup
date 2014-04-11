// Copyright 2003-2005, 2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OADocument.h>

#import <OmniAppKit/OAApplication.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OADocument
{
    NSString *_scriptIdentifier;
    NSScriptObjectSpecifier *_objectSpecifier;
}

- (void)dealloc;
{
    [_scriptIdentifier release];
    [_objectSpecifier release];
    [super dealloc];
}

#pragma mark - AppleScript

- (NSString *)scriptIdentifier;
{
    while (!_scriptIdentifier || [NSApp valueInOrderedDocumentsWithUniqueID:_scriptIdentifier ignoringDocument:self]) {
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
    
    NSScriptClassDescription *desc = [NSScriptClassDescription classDescriptionForClass:[NSApp class]];
    _objectSpecifier = [[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:desc
                                                                   containerSpecifier:nil
                                                                                  key:@"orderedDocuments"
                                                                             uniqueID:self.scriptIdentifier];
    return _objectSpecifier;
}

- (void)canCloseDocument:(void (^)(BOOL shouldClose))completion;
{
    completion = [[completion copy] autorelease];
    OBStrongRetain(completion); // Doing this so later conversion to ARC doesn't fool us into getting rid of the retain-until-called hack.
    [super canCloseDocumentWithDelegate:self shouldCloseSelector:@selector(_oa_document:shouldClose:contextInfo:) contextInfo:completion];
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

- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)shouldCloseSelector contextInfo:(void *)contextInfo;
{
    void (^completion)(BOOL) = ^(BOOL shouldClose){
        // - (void)document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo;
        void (*imp)(id, SEL, id, BOOL, void *) = (typeof(imp))objc_msgSend;
        imp(delegate, shouldCloseSelector, self, shouldClose, contextInfo);
    };
    
    [self canCloseDocument:completion];
}

@end
