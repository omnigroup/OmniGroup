// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFBundleRegistryTarget.h>

@class NSArray, NSMutableArray, NSString;
@class OFBundledClass;
@class OWContentType, OWURL;

@interface OWProcessorDescription : OFObject <OFBundleRegistryTarget>
{
    NSString *bundlePath;
    NSString *name;
    NSString *description;
    NSMutableArray *sourceContentTypes;

    BOOL usesNetwork;
    NSDictionary *proxiedTypeTable;
    
    NSString *processorClassName;
    OFBundledClass *processorClass;
}

+ (OWProcessorDescription *) processorDescriptionForProcessorClassName: (NSString *) className;
+ (OWProcessorDescription *) createUnregisteredProcessorDescriptionForProcessorClassName: (NSString *) className;

+ (NSArray *) processorDescriptions;

- (NSArray *) sourceContentTypes;

- (NSString *) processorClassName;
- (OFBundledClass *) processorClass;

- (NSString *) bundlePath;
- (void) setBundlePath: (NSString *) aPath;

- (NSString *) name;
- (void) setName: (NSString *) name;

- (NSString *) description;
- (void) setDescription: (NSString *) aDescription;

- (BOOL)usesNetwork;
- (void)setUsesNetwork:(BOOL)yn;

// Used to substitute a different processor when fetching a page via a proxy.
- (OWContentType *)contentTypeForURL:(OWURL *)request whenProxiedBy:(OWURL *)proxy;

- (void) registerProcessesContentType: (OWContentType *) sourceContentType toContentType:(OWContentType *)resultContentType cost:(float)cost;
- (void) registerProcessesContentType: (OWContentType *) sourceContentType toContentType:(OWContentType *)resultContentType cost:(float)cost producingSource:(BOOL)resultMayBeSource;

@end



