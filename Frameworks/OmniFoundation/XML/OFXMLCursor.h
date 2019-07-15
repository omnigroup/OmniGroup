// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSArray;
@class OFXMLDocument, OFXMLElement;

@interface OFXMLCursor : NSObject

- initWithDocument:(OFXMLDocument *)document element:(OFXMLElement *)element;
- initWithDocument:(OFXMLDocument *)document;

@property(nonatomic,readonly) OFXMLDocument *document;

@property(nonatomic,readonly) OFXMLElement *currentElement;
@property(nonatomic,readonly) id currentChild;
@property(nonatomic,readonly) NSString *currentPath;

@property(nonatomic,readonly) id nextChild;
- (id)peekNextChild;
- (void)openElement;
- (void)closeElement;

// Convenience methods that forward to -currentElement
@property(nonatomic,readonly) NSString *name;
@property(nonatomic,readonly) NSArray *children;
- (NSString *)attributeNamed:(NSString *)attributeName;

// More complex convenience methods
- (BOOL)openNextChildElementNamed:(NSString *)childElementName;

@end

// Error generating functions
extern NSString * const OFXMLLoadError;
extern void OFXMLRejectElement(OFXMLCursor *cursor);
