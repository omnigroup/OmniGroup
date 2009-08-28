// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLUnparsedElement.h>

#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLBuffer.h>

RCS_ID("$Id$")

@implementation OFXMLUnparsedElement

// The data is always UTF-8 right now.
- initWithName:(NSString *)name data:(NSData *)data; 
{
    _name = [name copy];
    _data = [data copy];
    return self;
}

- (void)dealloc;
{
    [_name release];
    [_data release];
    [super dealloc];
}

// Needed for -[OFXMLElement firstChildNamed:]
- (NSString *)name;
{
    return _name;
}

- (NSData *)data;
{
    return _data;
}

- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    OFXMLBufferAppendUTF8Data(xml, (CFDataRef)_data);
    return YES;
}

- (BOOL)xmlRepresentationCanContainChildren;
{
    return YES;
}

#pragma mark -
#pragma mark Comparison

- (BOOL)isEqual:(id)otherObject;
{
    // This means we don't consider OFXMLElement, OFXMLFrozenElement or OFXMLUnparsedElement the same, even if they would produce the same output.  Not sure if this is a bug; let's catch this case here to see if it ever hits.
    OBPRECONDITION([otherObject isKindOfClass:[OFXMLUnparsedElement class]]);
    if (![otherObject isKindOfClass:[OFXMLUnparsedElement class]])
        return NO;
    
    OFXMLUnparsedElement *otherElement = otherObject;

    return OFISEQUAL(_name, otherElement->_name) && OFISEQUAL(_data, otherElement->_data);
}

@end
