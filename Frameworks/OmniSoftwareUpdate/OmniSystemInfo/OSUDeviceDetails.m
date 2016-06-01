// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUDeviceDetails.h>

RCS_ID("$Id$");

static NSString * const OSUDeviceNameJSONKey = @"name";
static NSString * const OSUDevicePlatformJSONKey = @"platform";

static NSDictionary *OSULoadDeviceJSON(void) {
    static NSDictionary *devices = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [OMNI_BUNDLE pathForResource:@"OSUDevices" ofType:@"json"];
        NSData *data = [NSData dataWithContentsOfFile:path];
        devices = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    });
    
    OBPOSTCONDITION([devices isKindOfClass:[NSDictionary class]]);
    return devices;
}

NSString *OSUCopyDeviceNameForModel(NSString *hardwareModel)
{
    NSDictionary *json = OSULoadDeviceJSON();
    if (json == nil) {
        return nil;
    }
    
    NSDictionary *deviceInfo = json[hardwareModel];
    if (deviceInfo != nil) {
        NSString *name = deviceInfo[OSUDeviceNameJSONKey];
        OBASSERT(name != nil, @"Every device info blob should have a name.");
        return name;
    }
    
    // The hardware model on iOS devices is the weird character identifier (e.g. N66AP), *not* the major-minor identifier (e.g. iPhone8,2).
    // But they're easily confused (especially since they flip on OS X vs. iOS), so if we didn't find anything above, see if we got the platform instead and key on that.
    const char *functionName = __FUNCTION__; // capture this early in case we need to log it later
    for (NSString *model in json) {
        NSDictionary *candidateInfo = json[model];
        if ([candidateInfo[OSUDevicePlatformJSONKey] isEqualToString:hardwareModel]) {
            // Found it by the "wrong" key. Warn, but return reasonable results anyway.
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                NSLog(@"iOS products are identified by their hardware model (e.g. N66AP), not their 'machine' or 'platform' identifier (e.g. iPhone8,2). %s may return incorrect results when called with a platform identifier. Warning once only.", functionName);
            });
            
            NSString *name = candidateInfo[OSUDeviceNameJSONKey];
            OBASSERT(name != nil, @"Every device info blob should have a name.");
            return name;
        }
    }
    
    return nil;
}
