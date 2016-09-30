// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWProcessorDescription.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContentType.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")


static NSLock *registrationLock = nil;
static NSMutableDictionary *descriptionByName = nil;
static NSMutableArray *allDescriptions;

@implementation OWProcessorDescription

+ (void)initialize;
{
    OBINITIALIZE;
    
    registrationLock = [[NSLock alloc] init];
    descriptionByName = [[NSMutableDictionary alloc] init];
    allDescriptions = [[NSMutableArray alloc] init];
}

+ (OWProcessorDescription *)processorDescriptionForProcessorClassName:(NSString *)className;
{
    [registrationLock lock];
    OWProcessorDescription *aDescription = [descriptionByName objectForKey: className];
    if (!aDescription) {
        aDescription = [[self alloc] _initWithProcessorClassName: className];
        [descriptionByName setObject: aDescription forKey: className];
        [allDescriptions addObject: aDescription];
    }
    [registrationLock unlock];

    return aDescription;
}

/*" Returns a new autoreleased processor description that is not registered in the cache queried by +processorDescriptionForProcessorClassName:.  This is necessary for implementing processors where one class has multiple pieces of functionality and wants to report them seperately and register them in code, rather than through the Info plist in the processor bundle.  A good example of this is the Netscape plugin support in OmniWeb.  One ObjC class represents all of the Netscape plugins, but we want a different plugin description for each Netscape plugin so that JavaScript can report each Netscape plugin on its own. "*/
+ (OWProcessorDescription *)createUnregisteredProcessorDescriptionForProcessorClassName:(NSString *)className;
{
    OWProcessorDescription *aDescription = [[self alloc] _initWithProcessorClassName:className];
    [registrationLock lock];
    [allDescriptions addObject:aDescription];
    [registrationLock unlock];
    
    return aDescription;
}

+ (NSArray *)processorDescriptions;
{
    [registrationLock lock];
    NSArray *processorDescriptions = [[NSArray alloc] initWithArray:allDescriptions];
    [registrationLock unlock];
    
    return processorDescriptions;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return [super init];
}

- (NSString *)processorClassName;
{
    return processorClassName;
}

- (NSArray *)sourceContentTypes;
{
    return sourceContentTypes;
}

- (OFBundledClass *)processorClass;
{
    if (processorClass == nil)
        processorClass = [OFBundledClass bundledClassNamed:processorClassName];
    return processorClass;
}

- (NSString *)bundlePath;
{
    return bundlePath;
}

- (void)setBundlePath:(NSString *)aPath;
{
    bundlePath = [aPath copy];
}

- (NSString *)name;
{
    return name;
}

- (void)setName:(NSString *)aName;
{
    name = [aName copy];
}

- (NSString *)description;
{
    return description;
}

- (void)setDescription:(NSString *)aDescription;
{
    description = [aDescription copy];
}

- (BOOL)usesNetwork;
{
    return usesNetwork;
}

- (void)setUsesNetwork:(BOOL)yn
{
    usesNetwork = yn;
}

- (OWContentType *)contentTypeForURL:(OWURL *)request whenProxiedBy:(OWURL *)proxy;
{
    if (proxiedTypeTable) {
        OWContentType *aType = [proxiedTypeTable objectForKey:[proxy scheme]];
        if (aType != nil)
            return aType;
        aType = [proxiedTypeTable objectForKey:@"*"];
        if (aType != nil)
            return aType;
    }
    return [proxy contentType];
}

- (void)registerProcessesContentType:(OWContentType *)sourceContentType toContentType:(OWContentType *)resultContentType cost:(float)cost;
{
    [self registerProcessesContentType:sourceContentType toContentType:resultContentType cost:cost producingSource:NO];
}

- (void)registerProcessesContentType:(OWContentType *)sourceContentType toContentType:(OWContentType *)resultContentType cost:(float)cost producingSource:(BOOL)resultMayBeSource;
{
    [sourceContentTypes addObject:sourceContentType];
    [sourceContentType linkToContentType:resultContentType usingProcessorDescription:self cost:cost];
    if (resultMayBeSource) {
        // This allows the planner in OWContentType to find a path for targets which want "source" but don't care what kind of source they get, e.g. the downloader. It might be better to put a "result is source" bit on the OWContentTypeLink instead. But this works for now.
        [sourceContentType linkToContentType:[OWContentType sourceContentType] usingProcessorDescription:self cost:cost];
    }
}

// OFBundleRegistryTarget informal protocol

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)descriptionDict;
{
    [OFBundledClass createBundledClassWithName:itemName bundle:bundle description:descriptionDict];

    OWProcessorDescription *processorDescription = [self processorDescriptionForProcessorClassName: itemName];
    [processorDescription setBundlePath: [bundle bundlePath]];

    NSString *descriptionString = [descriptionDict objectForKey: @"description"];
    if (descriptionString)
        [processorDescription setDescription: descriptionString];
    
    NSString *nameString = [descriptionDict objectForKey: @"name"];
    if (nameString)
        [processorDescription setName: nameString];

    BOOL acceptsAddresses = NO;
    NSEnumerator *conversionEnumerator = [[descriptionDict objectForKey:@"converts"] objectEnumerator];
    for (NSDictionary *conversionDictionary in conversionEnumerator) {
	OWContentType *inputType = [OWContentType contentTypeForString:[conversionDictionary objectForKey:@"input"]];
	OWContentType *outputType = [OWContentType contentTypeForString:[conversionDictionary objectForKey:@"output"]];
	NSString *aCostObject = [conversionDictionary objectForKey:@"cost"];
	float aCost = aCostObject ? [aCostObject floatValue] : 1.0f;
        BOOL dothProduceSourceForsooth = [conversionDictionary boolForKey:@"source" defaultValue:NO];
        
        [processorDescription registerProcessesContentType: inputType toContentType: outputType cost: aCost producingSource: dothProduceSourceForsooth];
        
        if ([[inputType contentTypeString] hasPrefix:@"url/"])
            acceptsAddresses = YES;
    }
    
    BOOL networkFlag = [descriptionDict boolForKey: @"network" defaultValue: acceptsAddresses];
    [processorDescription setUsesNetwork: networkFlag];

    id proxyBehavior = [descriptionDict objectForKey:@"proxied-type"];
    if (proxyBehavior) {
        if ([proxyBehavior isKindOfClass:[NSString class]])
            [processorDescription setProxyTypes: [NSDictionary dictionaryWithObject:proxyBehavior forKey:@"*"]];
        else
            [processorDescription setProxyTypes: proxyBehavior];
    }
}

// Debugging

- (NSMutableDictionary *) debugDictionary;
{
    NSMutableDictionary *dict;
    
    dict = [super debugDictionary];
    [dict setObject: processorClassName forKey: @"processorClassName"];
    [dict setObject: sourceContentTypes forKey: @"sourceContentTypes"];
    if (bundlePath)
        [dict setObject: bundlePath forKey: @"bundlePath"];
    if (description)
        [dict setObject: description forKey: @"description"];
    if (name)
        [dict setObject: name forKey: @"name"];
    if (proxiedTypeTable)
        [dict setObject: proxiedTypeTable forKey: @"proxiedTypeTable"];
    [dict setBoolValue: usesNetwork forKey: @"network"];
    [dict setBoolValue: (processorClass && [processorClass isLoaded]) forKey: @"isLoaded"];
    
    return dict;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"%@ (%@)", OBShortObjectDescription(self), processorClassName];
}

#pragma mark - OWProcessorDescription (Internal)

- (instancetype)_initWithProcessorClassName:(NSString *)className;
{
    if (!(self = [super init]))
        return nil;

    processorClassName = [className copy];
    description = processorClassName;
    name = processorClassName;
    sourceContentTypes = [[NSMutableArray alloc] init];
    bundlePath = [[NSBundle mainBundle] bundlePath];
    
    return self;
}

- (void)setProxyTypes:(NSDictionary *)proxyBehavior;
{
    NSMutableDictionary *proxyTable = proxiedTypeTable? [proxiedTypeTable mutableCopy] : [[NSMutableDictionary alloc] init];

    OBASSERT([proxyBehavior isKindOfClass:[NSDictionary class]]);
    NSEnumerator *schemes = [proxyBehavior keyEnumerator];
    for (NSString *scheme in schemes) {
        [proxyTable setObject:[OWContentType contentTypeForString:[proxyBehavior objectForKey:scheme]] forKey:scheme];
    }

    proxiedTypeTable = [proxyTable copy];
}

@end


