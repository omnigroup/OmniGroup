// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLFrozenElement.h>

#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLString.h>

#import <OmniFoundation/OFXMLBuffer.h>

RCS_ID("$Id$");

#define SAFE_ALLOCA_SIZE (8 * 8192)

@implementation OFXMLFrozenElement

- initWithName:(NSString *)name children:(NSArray *)children attributes:(NSDictionary *)attributes attributeOrder:(NSArray *)attributeOrder;
{
    _name = [name copy];

    // Create with a fixed capacity
    unsigned int childIndex, childCount = [children count];
    if (childCount) {
        NSMutableArray *frozenChildren = (NSMutableArray *)CFArrayCreateMutable(kCFAllocatorDefault, childCount, &OFNSObjectArrayCallbacks);
        for (childIndex = 0; childIndex < childCount; childIndex++) {
            id child = [[children objectAtIndex:childIndex] copyFrozenElement];
            [frozenChildren addObject:child];
            [child release];
        }

        _children = [[NSArray alloc] initWithArray:frozenChildren];
        [frozenChildren release];
    }

    if (attributeOrder) {
        unsigned int attributeIndex, attributeCount = [attributeOrder count];

	// Should only be a few attributes in the vastly common case
	size_t bufferSize = 2*attributeCount*sizeof(id);
	BOOL useMalloc = bufferSize >= SAFE_ALLOCA_SIZE;	
	
	id *buffer = useMalloc ? (id *)malloc(bufferSize) : (id *)alloca(bufferSize);
	unsigned int bufferIndex = 0;

        for (attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
            NSString *attributeName = [attributeOrder objectAtIndex:attributeIndex];
            NSString *attributeValue = [attributes objectForKey:attributeName];
            if (!attributeValue)
                continue;

            // TODO: It would be nice to pre-quote the values here, but that would require us to know the target encoding (and then if the user decided to change encodings, we'd need to be able to deal with that somehow).
	    buffer[bufferIndex + 0] = attributeName;
	    buffer[bufferIndex + 1] = attributeValue;
	    bufferIndex += 2;
        }

        _attributeNamesAndValues = [[NSArray alloc] initWithObjects:buffer count:bufferIndex];
	if (useMalloc)
	    free(buffer);
    }

    return self;
}

- (void)dealloc;
{
    [_name release];
    [_children release];
    [_attributeNamesAndValues release];
    [super dealloc];
}

// Needed for -[OFXMLElement firstChildNamed:]
- (NSString *)name;
{
    return _name;
}

// This is mostly the same as the OFXMLElement version, but trimmed down to reflect the different storage format
- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    OFXMLWhitespaceBehaviorType whitespaceBehavior;

    whitespaceBehavior = [[doc whitespaceBehavior] behaviorForElementName: _name];
    if (whitespaceBehavior == OFXMLWhitespaceBehaviorTypeAuto)
        whitespaceBehavior = parentBehavior;

    OFXMLBufferAppendUTF8CString(xml, "<");
    OFXMLBufferAppendString(xml, (CFStringRef)_name);

    if (_attributeNamesAndValues) {
        // Quote the attribute values
        CFStringEncoding encoding = [doc stringEncoding];
        unsigned int attributeIndex, attributeCount = [_attributeNamesAndValues count] / 2;
        for (attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
            NSString *name  = [_attributeNamesAndValues objectAtIndex:2*attributeIndex+0];
            NSString *value = [_attributeNamesAndValues objectAtIndex:2*attributeIndex+1];
            
            OFXMLBufferAppendUTF8CString(xml, " ");
            OFXMLBufferAppendString(xml, (CFStringRef)name);

            OFXMLBufferAppendUTF8CString(xml, "=\"");
            NSString *quotedString = OFXMLCreateStringWithEntityReferencesInCFEncoding(value, OFXMLBasicEntityMask, nil, encoding);
            OFXMLBufferAppendString(xml, (CFStringRef)quotedString);
            [quotedString release];
            OFXMLBufferAppendUTF8CString(xml, "\"");
        }
    }

    BOOL hasWrittenChild = NO;
    BOOL doIntenting = NO;

    // See if any of our children are non-ignored and use this for isEmpty instead of the plain count
    unsigned int childIndex, childCount = [_children count];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        id child = [_children objectAtIndex:childIndex];

        // If we have actual element children and whitespace isn't important for this node, do some formatting.
        // We will produce output that is a little strange for something like '<x>foo<y/></x>' or any other mix of string and element children, but usually whitespace is important in this case and it won't be an issue.
        if (whitespaceBehavior == OFXMLWhitespaceBehaviorTypeIgnore)  {
            doIntenting = [child xmlRepresentationCanContainChildren];
        }

        // Close off the parent tag if this is the first child
        if (!hasWrittenChild)
            OFXMLBufferAppendUTF8CString(xml, ">");

        if (doIntenting) {
            OFXMLBufferAppendUTF8CString(xml, "\n");
            OFXMLBufferAppendSpaces(xml, 2*(level + 1));
        }

        if (![child appendXML:xml withParentWhiteSpaceBehavior:whitespaceBehavior document:doc level:level+1 error:outError])
            return NO;

        hasWrittenChild = YES;
    }

    if (doIntenting) {
        OFXMLBufferAppendUTF8CString(xml, "\n");
        OFXMLBufferAppendSpaces(xml, 2*level);
    }

    if (hasWrittenChild) {
        OFXMLBufferAppendUTF8CString(xml, "</");
        OFXMLBufferAppendString(xml, (CFStringRef)_name);
        OFXMLBufferAppendUTF8CString(xml, ">");
    } else
        OFXMLBufferAppendUTF8CString(xml, "/>");

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
    OBPRECONDITION([otherObject isKindOfClass:[OFXMLFrozenElement class]]);
    if (![otherObject isKindOfClass:[OFXMLFrozenElement class]])
        return NO;
    
    OFXMLFrozenElement *otherElement = otherObject;
    
    if (OFNOTEQUAL(_name, otherElement->_name))
        return NO;

    if ([_attributeNamesAndValues count] != 0 || [otherElement->_attributeNamesAndValues count] != 0) {
        if (OFNOTEQUAL(_attributeNamesAndValues, otherElement->_attributeNamesAndValues))
            return NO;
    }

    if ([_children count] != 0 || [otherElement->_children count] != 0) {
        if (OFNOTEQUAL(_children, otherElement->_children))
            return NO;
    }
    
    return YES;
}

@end
