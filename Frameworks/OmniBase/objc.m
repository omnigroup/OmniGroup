// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/objc.h>

#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

void OBEnumerateProtocolsForClassConformingToProtocol(Class cls, Protocol * _Nullable conformingToProtocol, OBProtocolAction action)
{
    unsigned int protocolCount;
    Protocol * __unsafe_unretained *protocols = class_copyProtocolList(cls, &protocolCount);
    if (protocols == NULL)
        return;

    for (unsigned int protocolIndex = 0; protocolIndex < protocolCount; protocolIndex++) {
        Protocol *protocol = protocols[protocolIndex];

        // Don't include the conformingToProtocol itself, if specified
        if (protocol == conformingToProtocol)
            continue;

        if (conformingToProtocol && protocol_conformsToProtocol(protocol, conformingToProtocol)) {
            action(protocol);
        }
    }

    free(protocols);
}

void OBEnumeratePropertiesInProtocol(Protocol *protocol, OBPropertyAction action)
{
    unsigned int propertyCount;
    objc_property_t *properties = protocol_copyPropertyList(protocol, &propertyCount);
    if (!properties) {
        return;
    }

    for (unsigned int propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
        action(properties[propertyIndex]);
    }

    free(properties);
}

void OBEnumerateMethodDescriptionsInProtocol(Protocol *protocol, BOOL isInstanceMethod, OBMethodDescriptionAction action)
{
    unsigned int methodDescriptionCount;
    struct objc_method_description *methodDescriptions = protocol_copyMethodDescriptionList(protocol, YES/*isRequiredMethod*/, isInstanceMethod, &methodDescriptionCount);
    if (methodDescriptions == NULL) {
        return;
    }

    for (unsigned int methodDescriptionIndex = 0; methodDescriptionIndex < methodDescriptionCount; methodDescriptionIndex++) {
        action(methodDescriptions[methodDescriptionIndex]);
    }
    
    free(methodDescriptions);
}

/*"
 Ensures that the given selName maps to a registered selector.  If it doesn't, a copy of the string is made and it is registered with the runtime.  The registered selector is returned, in any case.
 "*/
SEL OBRegisterSelectorIfAbsent(const char *selName)
{
    SEL sel;

    if (!(sel = sel_getUid(selName))) {
        // The documentation isn't clear on whether the input string is copied or not.
        // On NS4.0 and later, sel_registerName copies the selector name.  But
        // we won't assume that is the case -- we'll make a temporary copy
        // and get the assertion rather than crashing the runtime (in case they
        // change this in the future).
        char *newSel = strdup(selName);
        sel = sel_registerName(newSel);

        // Make sure the copy happened
        OBASSERT((void *)sel_getUid(selName) != (void *)newSel);
        OBASSERT((void *)sel != (void *)newSel);

        free(newSel);
    }
    
    return sel;
}


SEL OBSetterForName(const char *name)
{
    // Sadly, -capitalizedString uppercases the first character, but lowercases all the rest. I don't see a good way to do what we want in a Unicode friendly way. We'll just warn and make the property read-only if we get a non-ASCII property name.
    size_t nameLength = strlen(name);
    char *setString = (char *)malloc(3 + nameLength + 1 + 1); // set<name>: + NUL

    setString[0] = 's';
    setString[1] = 'e';
    setString[2] = 't';
    memcpy(&setString[3], name, nameLength);
    setString[3] = toupper(setString[3]);

    setString[3+nameLength] = ':';
    setString[4+nameLength] = 0;

    SEL setterSelector = OBRegisterSelectorIfAbsent(setString);

    free(setString);

    return setterSelector;
}

_Nullable Class OBSuperclass(Class cls)
{
    return [cls superclass];
}

NS_ASSUME_NONNULL_END
