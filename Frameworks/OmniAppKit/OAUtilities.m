// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAUtilities.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/OmniGroup/Frameworks/OmniAppKit/OAUtilities.m 124296 2010-01-25 16:51:27Z bungi $");

BOOL OAPushValueThroughBinding(id self, id objectValue, NSString *binding)
{
    NSDictionary *bindingInfo = [self infoForBinding:binding];
    if (!bindingInfo)
        return NO;
    
    NSDictionary *bindingOptions = [bindingInfo objectForKey:NSOptionsKey];
    NSValueTransformer *transformer;
    if ((transformer = [bindingOptions objectForKey:NSValueTransformerBindingOption])) {
        objectValue = [transformer reverseTransformedValue:objectValue];
    } else {
        NSString *transformerName = [bindingOptions objectForKey:NSValueTransformerNameBindingOption];
        if (transformerName) {
            NSValueTransformer *transformer = [NSValueTransformer valueTransformerForName:transformerName];
            OBASSERT(transformer);
            if (transformer)
                objectValue = [transformer reverseTransformedValue:objectValue]; // don't nullify the value if the transformer name references something that doesn't exist
        }
    }
    
    id observedObject = [bindingInfo objectForKey:NSObservedObjectKey];
    OBASSERT(observedObject);
    [observedObject setValue:objectValue forKeyPath:[bindingInfo objectForKey:NSObservedKeyPathKey]];
    return YES;
}

